#include <jni.h>

#include <android/log.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-port.h>
#include <gphoto2/gphoto2-version.h>

#define LOG_TAG "CameraeGPhoto2"
#define REPORT_CAPACITY 65536

typedef struct {
    char data[REPORT_CAPACITY];
    size_t length;
} ProbeReport;

static void report_append(ProbeReport *report, const char *format, ...) {
    if (report->length >= REPORT_CAPACITY - 1) return;
    va_list args;
    va_start(args, format);
    int written = vsnprintf(
            report->data + report->length,
            REPORT_CAPACITY - report->length,
            format,
            args
    );
    va_end(args);
    if (written <= 0) return;
    size_t available = REPORT_CAPACITY - report->length;
    report->length += (size_t) written < available ? (size_t) written : available - 1;
}

static void context_error(GPContext *context, const char *message, void *data) {
    (void) context;
    ProbeReport *report = data;
    report_append(report, "[libgphoto2:error] %s\n", message);
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s", message);
}

static void context_status(GPContext *context, const char *message, void *data) {
    (void) context;
    ProbeReport *report = data;
    report_append(report, "[libgphoto2:status] %s\n", message);
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "%s", message);
}

static int contains_relevant_name(const char *value) {
    if (!value) return 0;
    char lower[128];
    size_t length = strlen(value);
    if (length >= sizeof(lower)) length = sizeof(lower) - 1;
    for (size_t i = 0; i < length; ++i) lower[i] = (char) tolower((unsigned char) value[i]);
    lower[length] = '\0';
    return strstr(lower, "iso") != NULL
            || strstr(lower, "whitebalance") != NULL
            || strstr(lower, "white balance") != NULL
            || strstr(lower, "shutter") != NULL
            || strstr(lower, "bulb") != NULL
            || strstr(lower, "capturetarget") != NULL
            || strstr(lower, "capture target") != NULL;
}

static void append_widget_value(ProbeReport *report, CameraWidget *widget, CameraWidgetType type) {
    int result;
    if (type == GP_WIDGET_TEXT || type == GP_WIDGET_MENU || type == GP_WIDGET_RADIO) {
        const char *value = NULL;
        result = gp_widget_get_value(widget, &value);
        if (result >= GP_OK && value) report_append(report, "%s", value);
    } else if (type == GP_WIDGET_RANGE) {
        float value = 0.0f;
        result = gp_widget_get_value(widget, &value);
        if (result >= GP_OK) report_append(report, "%.3f", value);
    } else if (type == GP_WIDGET_TOGGLE || type == GP_WIDGET_DATE) {
        int value = 0;
        result = gp_widget_get_value(widget, &value);
        if (result >= GP_OK) report_append(report, "%d", value);
    } else {
        report_append(report, "<grupo>");
    }
}

static void append_relevant_widgets(ProbeReport *report, CameraWidget *widget) {
    const char *name = NULL;
    const char *label = NULL;
    CameraWidgetType type;
    gp_widget_get_name(widget, &name);
    gp_widget_get_label(widget, &label);
    gp_widget_get_type(widget, &type);

    if (contains_relevant_name(name) || contains_relevant_name(label)) {
        report_append(report, "- %s [%s] = ", label ? label : "sem label", name ? name : "sem nome");
        append_widget_value(report, widget, type);
        int choices = gp_widget_count_choices(widget);
        if (choices > 0) {
            report_append(report, " | opções: ");
            int limit = choices > 40 ? 40 : choices;
            for (int i = 0; i < limit; ++i) {
                const char *choice = NULL;
                if (gp_widget_get_choice(widget, i, &choice) >= GP_OK && choice) {
                    report_append(report, "%s%s", i == 0 ? "" : ", ", choice);
                }
            }
            if (choices > limit) report_append(report, ", … (%d no total)", choices);
        }
        report_append(report, "\n");
    }

    int children = gp_widget_count_children(widget);
    for (int i = 0; i < children; ++i) {
        CameraWidget *child = NULL;
        if (gp_widget_get_child(widget, i, &child) >= GP_OK && child) {
            append_relevant_widgets(report, child);
        }
    }
}

JNIEXPORT jstring JNICALL
Java_com_camerae_eosrprobe_NativeGPhotoClient_nativeProbe(
        JNIEnv *env,
        jclass clazz,
        jint file_descriptor,
        jstring camlib_directory,
        jstring iolib_directory
) {
    (void) clazz;
    ProbeReport report = {{0}, 0};
    const char *camlibs = (*env)->GetStringUTFChars(env, camlib_directory, NULL);
    const char *iolibs = (*env)->GetStringUTFChars(env, iolib_directory, NULL);
    if (!camlibs || !iolibs) {
        if (camlibs) (*env)->ReleaseStringUTFChars(env, camlib_directory, camlibs);
        if (iolibs) (*env)->ReleaseStringUTFChars(env, iolib_directory, iolibs);
        return (*env)->NewStringUTF(env, "ERRO: não foi possível preparar os diretórios nativos.");
    }

    setenv("CAMLIBS", camlibs, 1);
    setenv("IOLIBS", iolibs, 1);
    report_append(&report, "PROBE LIBGPHOTO2 SOMENTE LEITURA\n");
    report_append(&report, "fd Android: %d\nCAMLIBS: %s\nIOLIBS: %s\n", file_descriptor, camlibs, iolibs);
    (*env)->ReleaseStringUTFChars(env, camlib_directory, camlibs);
    (*env)->ReleaseStringUTFChars(env, iolib_directory, iolibs);

    const char **version = gp_library_version(GP_VERSION_SHORT);
    report_append(&report, "libgphoto2: %s\n", version && version[0] ? version[0] : "desconhecida");

    int result = gp_port_usb_set_sys_device(file_descriptor);
    report_append(&report, "gp_port_usb_set_sys_device: %d (%s)\n", result, gp_result_as_string(result));
    if (result < GP_OK) return (*env)->NewStringUTF(env, report.data);

    GPContext *context = gp_context_new();
    Camera *camera = NULL;
    CameraWidget *configuration = NULL;
    int initialized = 0;
    if (!context) {
        report_append(&report, "ERRO: gp_context_new retornou null.\n");
        return (*env)->NewStringUTF(env, report.data);
    }
    gp_context_set_error_func(context, context_error, &report);
    gp_context_set_status_func(context, context_status, &report);

    result = gp_camera_new(&camera);
    report_append(&report, "gp_camera_new: %d (%s)\n", result, gp_result_as_string(result));
    if (result >= GP_OK) {
        result = gp_camera_init(camera, context);
        report_append(&report, "gp_camera_init: %d (%s)\n", result, gp_result_as_string(result));
        initialized = result >= GP_OK;
    }

    if (initialized) {
        CameraText summary;
        memset(&summary, 0, sizeof(summary));
        result = gp_camera_get_summary(camera, &summary, context);
        report_append(&report, "gp_camera_get_summary: %d (%s)\n", result, gp_result_as_string(result));
        if (result >= GP_OK) report_append(&report, "\nRESUMO DA CÂMERA\n%s\n", summary.text);

        result = gp_camera_get_config(camera, &configuration, context);
        report_append(&report, "gp_camera_get_config: %d (%s)\n", result, gp_result_as_string(result));
        if (result >= GP_OK && configuration) {
            report_append(&report, "\nCONTROLES ASTRO ENCONTRADOS\n");
            append_relevant_widgets(&report, configuration);
        }
    }

    if (configuration) gp_widget_free(configuration);
    if (camera) {
        if (initialized) {
            int exit_result = gp_camera_exit(camera, context);
            report_append(&report, "gp_camera_exit: %d (%s)\n", exit_result, gp_result_as_string(exit_result));
        }
        gp_camera_free(camera);
    }
    gp_context_unref(context);
    report_append(&report, "Fim do probe; nenhuma configuração foi escrita e nenhuma captura foi solicitada.\n");
    return (*env)->NewStringUTF(env, report.data);
}
