# Dependências nativas do probe Android

O APK `0.8.0` introduz um caminho experimental libgphoto2 somente leitura para a Canon EOS R. Os binários em `app/src/main/jniLibs/arm64-v8a` e os módulos em `app/src/main/assets/gphoto` foram compilados com Android NDK `27.0.12077973`, API 26, para `arm64-v8a`.

## Fontes fixadas

| Componente | Versão | SHA-256 do tarball | Fonte |
| --- | --- | --- | --- |
| libgphoto2 | 2.5.34 | `51993f5d9bfb6b4e5925cbbe5883085791bff6f81bcacb8ffe1b783ce76d586a` | `https://github.com/gphoto/libgphoto2/releases/download/v2.5.34/libgphoto2-2.5.34.tar.xz` |
| libusb | 1.0.29 | `5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85` | `https://github.com/libusb/libusb/releases/download/v1.0.29/libusb-1.0.29.tar.bz2` |
| GNU libltdl/libtool | 2.5.4 | `f81f5860666b0bc7d84baddefa60d1cb9fa6fceb2398cc3baca6afaa60266675` | `https://ftpmirror.gnu.org/libtool/libtool-2.5.4.tar.xz` |

Consulte os arquivos `COPYING` e `LICENSE` das fontes acima antes de redistribuir um build de produção. Esta inclusão é exclusiva do experimento e ainda precisa de uma revisão formal de distribuição para migração ao Camerae principal.

## Escopo da compilação

- Camlib: somente `ptp2`, que contém o suporte da Canon EOS R.
- I/O: módulo `usb1` usando libusb 1.0.
- `libusb_wrap_sys_device`: habilitado; recebe o file descriptor autorizado pelo `UsbDeviceConnection` do Android.
- JPEG, XML, curl, GD, TIFF, EXIF, traduções e camlibs não relacionados: desabilitados.
- Arquitetura do primeiro dispositivo: somente `arm64-v8a`.

O aviso de “non-standard set of camlibs” é esperado porque foi usado `--with-camlibs=ptp2`. Ele alerta sobre suporte genérico a câmeras, mas não indica ausência do driver da EOS R. Antes de ampliar a compatibilidade para outras famílias, o conjunto de camlibs deve ser reavaliado.

## Bibliotecas empacotadas

```text
jniLibs/arm64-v8a/libgphoto2.so
jniLibs/arm64-v8a/libgphoto2_port.so
jniLibs/arm64-v8a/libltdl.so
jniLibs/arm64-v8a/libusb-1.0.so
assets/gphoto/camlibs/ptp2.so
assets/gphoto/iolibs/usb1.so
```

Os módulos dinâmicos são extraídos para o armazenamento privado do app antes do primeiro probe. `CAMLIBS` e `IOLIBS` apontam exclusivamente para essas duas pastas, evitando que o carregador trate as bibliotecas de infraestrutura como drivers de câmera.
