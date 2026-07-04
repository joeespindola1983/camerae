package com.camerae.android;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.Settings;
import android.view.Gravity;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import java.io.InputStream;
import java.util.Collections;

public final class MainActivity extends Activity {
    private static final int REQUEST_CAMERA_PERMISSION = 10;
    private static final int REQUEST_REFERENCE_IMAGE = 11;

    private TextureView previewView;
    private AlignmentOverlayView overlayView;
    private TextView statusView;
    private HandlerThread cameraThread;
    private Handler cameraHandler;
    private CameraDevice cameraDevice;
    private CameraCaptureSession captureSession;
    private CaptureRequest.Builder previewRequestBuilder;
    private String cameraId;

    private final TextureView.SurfaceTextureListener textureListener = new TextureView.SurfaceTextureListener() {
        @Override
        public void onSurfaceTextureAvailable(SurfaceTexture surfaceTexture, int width, int height) {
            openCameraWhenAllowed();
        }

        @Override
        public void onSurfaceTextureSizeChanged(SurfaceTexture surfaceTexture, int width, int height) {
            overlayView.invalidate();
        }

        @Override
        public boolean onSurfaceTextureDestroyed(SurfaceTexture surfaceTexture) {
            return true;
        }

        @Override
        public void onSurfaceTextureUpdated(SurfaceTexture surfaceTexture) {
        }
    };

    private final CameraDevice.StateCallback cameraStateCallback = new CameraDevice.StateCallback() {
        @Override
        public void onOpened(CameraDevice camera) {
            cameraDevice = camera;
            startPreview();
        }

        @Override
        public void onDisconnected(CameraDevice camera) {
            camera.close();
            cameraDevice = null;
            setStatus("Camera desconectada");
        }

        @Override
        public void onError(CameraDevice camera, int error) {
            camera.close();
            cameraDevice = null;
            setStatus("Erro da camera: " + error);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        buildInterface();
    }

    @Override
    protected void onResume() {
        super.onResume();
        startCameraThread();
        if (previewView.isAvailable()) {
            openCameraWhenAllowed();
        } else {
            previewView.setSurfaceTextureListener(textureListener);
        }
    }

    @Override
    protected void onPause() {
        closeCamera();
        stopCameraThread();
        super.onPause();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_CAMERA_PERMISSION &&
                grantResults.length > 0 &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            openCameraWhenAllowed();
        } else if (requestCode == REQUEST_CAMERA_PERMISSION) {
            setStatus("Permissao da camera negada");
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_REFERENCE_IMAGE && resultCode == RESULT_OK && data != null) {
            loadReferenceImage(data.getData());
        }
    }

    private void buildInterface() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        previewView = new TextureView(this);
        root.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        overlayView = new AlignmentOverlayView(this);
        root.addView(overlayView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        statusView = new TextView(this);
        statusView.setText("Repeatable Android");
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(16);
        statusView.setGravity(Gravity.START);
        statusView.setBackgroundColor(0x55000000);
        statusView.setPadding(dp(12), dp(10), dp(12), dp(10));
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
        );
        root.addView(statusView, statusParams);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.setPadding(dp(12), dp(10), dp(12), dp(10));
        controls.setBackgroundColor(0x88000000);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.CENTER);

        Button importButton = new Button(this);
        importButton.setText("Referencia");
        importButton.setOnClickListener(view -> pickReferenceImage());
        buttons.addView(importButton, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        Button gridButton = new Button(this);
        gridButton.setText("Grid");
        gridButton.setOnClickListener(view -> {
            overlayView.setGridVisible(!overlayView.isGridVisible());
            setStatus(overlayView.isGridVisible() ? "Grid ligado" : "Grid desligado");
        });
        buttons.addView(gridButton, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        Button clearButton = new Button(this);
        clearButton.setText("Limpar");
        clearButton.setOnClickListener(view -> {
            overlayView.setReferenceBitmap(null);
            setStatus("Referencia removida");
        });
        buttons.addView(clearButton, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        controls.addView(buttons);

        TextView opacityLabel = new TextView(this);
        opacityLabel.setText("Opacidade da referencia");
        opacityLabel.setTextColor(Color.WHITE);
        opacityLabel.setPadding(0, dp(8), 0, 0);
        controls.addView(opacityLabel);

        SeekBar opacitySlider = new SeekBar(this);
        opacitySlider.setMax(100);
        opacitySlider.setProgress(45);
        opacitySlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                overlayView.setReferenceOpacity(progress / 100f);
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {
            }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {
            }
        });
        controls.addView(opacitySlider);

        FrameLayout.LayoutParams controlsParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
        );
        root.addView(controls, controlsParams);

        setContentView(root);
    }

    private void pickReferenceImage() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("image/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_REFERENCE_IMAGE);
    }

    private void loadReferenceImage(Uri uri) {
        if (uri == null) {
            return;
        }

        try (InputStream stream = getContentResolver().openInputStream(uri)) {
            Bitmap bitmap = BitmapFactory.decodeStream(stream);
            overlayView.setReferenceBitmap(bitmap);
            setStatus(bitmap == null ? "Referencia invalida" : "Referencia carregada");
        } catch (Exception error) {
            setStatus("Falha ao carregar referencia");
        }
    }

    private void startCameraThread() {
        cameraThread = new HandlerThread("CameraeCamera");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());
    }

    private void stopCameraThread() {
        if (cameraThread == null) {
            return;
        }

        cameraThread.quitSafely();
        try {
            cameraThread.join();
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }

        cameraThread = null;
        cameraHandler = null;
    }

    private void openCameraWhenAllowed() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.CAMERA}, REQUEST_CAMERA_PERMISSION);
            return;
        }

        openBackCamera();
    }

    private void openBackCamera() {
        if (cameraDevice != null || !previewView.isAvailable()) {
            return;
        }

        CameraManager manager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
        try {
            cameraId = findBackCameraId(manager);
            if (cameraId == null) {
                setStatus("Camera traseira nao encontrada");
                return;
            }

            manager.openCamera(cameraId, cameraStateCallback, cameraHandler);
            setStatus("Abrindo camera");
        } catch (SecurityException error) {
            setStatus("Permissao da camera necessaria");
        } catch (CameraAccessException error) {
            setStatus("Camera indisponivel");
        }
    }

    private String findBackCameraId(CameraManager manager) throws CameraAccessException {
        for (String id : manager.getCameraIdList()) {
            CameraCharacteristics characteristics = manager.getCameraCharacteristics(id);
            Integer facing = characteristics.get(CameraCharacteristics.LENS_FACING);
            if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                return id;
            }
        }

        String[] ids = manager.getCameraIdList();
        return ids.length == 0 ? null : ids[0];
    }

    private void startPreview() {
        if (cameraDevice == null || !previewView.isAvailable()) {
            return;
        }

        SurfaceTexture texture = previewView.getSurfaceTexture();
        if (texture == null) {
            return;
        }

        texture.setDefaultBufferSize(previewView.getWidth(), previewView.getHeight());
        Surface surface = new Surface(texture);

        try {
            previewRequestBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            previewRequestBuilder.addTarget(surface);
            previewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            previewRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);

            cameraDevice.createCaptureSession(
                    Collections.singletonList(surface),
                    new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(CameraCaptureSession session) {
                            captureSession = session;
                            try {
                                captureSession.setRepeatingRequest(
                                        previewRequestBuilder.build(),
                                        null,
                                        cameraHandler
                                );
                                setStatus("Camera pronta - Repeatable");
                            } catch (CameraAccessException error) {
                                setStatus("Preview falhou");
                            }
                        }

                        @Override
                        public void onConfigureFailed(CameraCaptureSession session) {
                            setStatus("Configuracao da camera falhou");
                        }
                    },
                    cameraHandler
            );
        } catch (CameraAccessException error) {
            setStatus("Nao foi possivel iniciar preview");
        }
    }

    private void closeCamera() {
        if (captureSession != null) {
            captureSession.close();
            captureSession = null;
        }

        if (cameraDevice != null) {
            cameraDevice.close();
            cameraDevice = null;
        }
    }

    private void setStatus(String status) {
        runOnUiThread(() -> statusView.setText(status));
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    public static final class AlignmentOverlayView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private Bitmap referenceBitmap;
        private boolean gridVisible = true;
        private float referenceOpacity = 0.45f;

        public AlignmentOverlayView(Context context) {
            super(context);
        }

        public boolean isGridVisible() {
            return gridVisible;
        }

        public void setGridVisible(boolean gridVisible) {
            this.gridVisible = gridVisible;
            invalidate();
        }

        public void setReferenceOpacity(float referenceOpacity) {
            this.referenceOpacity = Math.max(0f, Math.min(referenceOpacity, 1f));
            invalidate();
        }

        public void setReferenceBitmap(Bitmap referenceBitmap) {
            this.referenceBitmap = referenceBitmap;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            drawReference(canvas);
            if (gridVisible) {
                drawGrid(canvas);
            }
        }

        private void drawReference(Canvas canvas) {
            if (referenceBitmap == null) {
                return;
            }

            int saveCount = canvas.save();
            paint.setAlpha(Math.round(referenceOpacity * 255));
            paint.setFilterBitmap(true);

            Matrix matrix = scaledToFillMatrix(
                    referenceBitmap.getWidth(),
                    referenceBitmap.getHeight(),
                    getWidth(),
                    getHeight()
            );
            canvas.drawBitmap(referenceBitmap, matrix, paint);
            paint.setAlpha(255);
            canvas.restoreToCount(saveCount);
        }

        private void drawGrid(Canvas canvas) {
            float width = getWidth();
            float height = getHeight();
            float thirdX = width / 3f;
            float thirdY = height / 3f;

            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeWidth(1.5f);
            paint.setColor(0x99FFFFFF);

            canvas.drawLine(thirdX, 0, thirdX, height, paint);
            canvas.drawLine(thirdX * 2, 0, thirdX * 2, height, paint);
            canvas.drawLine(0, thirdY, width, thirdY, paint);
            canvas.drawLine(0, thirdY * 2, width, thirdY * 2, paint);

            paint.setColor(0x55FFFFFF);
            canvas.drawLine(0, 0, width, height, paint);
            canvas.drawLine(0, height, width, 0, paint);

            float cross = Math.min(width, height) * 0.055f;
            paint.setColor(0x66FFFFFF);
            canvas.drawLine(width / 2f - cross, height / 2f, width / 2f + cross, height / 2f, paint);
            canvas.drawLine(width / 2f, height / 2f - cross, width / 2f, height / 2f + cross, paint);

            paint.setStyle(Paint.Style.FILL);
            paint.setColor(0xCC40E0D0);
            canvas.drawCircle(thirdX, thirdY, 3.5f, paint);
            canvas.drawCircle(thirdX * 2, thirdY, 3.5f, paint);
            canvas.drawCircle(thirdX, thirdY * 2, 3.5f, paint);
            canvas.drawCircle(thirdX * 2, thirdY * 2, 3.5f, paint);
        }

        private Matrix scaledToFillMatrix(float sourceWidth, float sourceHeight, float targetWidth, float targetHeight) {
            float scale = Math.max(targetWidth / sourceWidth, targetHeight / sourceHeight);
            float scaledWidth = sourceWidth * scale;
            float scaledHeight = sourceHeight * scale;

            Matrix matrix = new Matrix();
            matrix.postScale(scale, scale);
            matrix.postTranslate((targetWidth - scaledWidth) / 2f, (targetHeight - scaledHeight) / 2f);
            return matrix;
        }
    }
}
