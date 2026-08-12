# Política de compatibilidade USB/PTP

## Níveis

| Nível | Comportamento |
| --- | --- |
| Validado para captura | Disparo, evento de novo objeto e download habilitados. |
| Importação somente | Identificação, inventário e download MTP habilitados; comandos de captura bloqueados. |
| Desconhecido | Somente topologia e log até confirmação manual. |

## Matriz atual

| Fabricante/modelo | VID:PID | Firmware testado | Nível |
| --- | --- | --- | --- |
| Canon EOS R | `04A9:32DA` | `3-1.8.0` | Validado para captura |
| Outras Canon PTP | `04A9:*` | — | Importação somente |
| Outros fabricantes | — | — | Desconhecido |

O app não presume que toda Canon EOS usa a mesma sequência. O núcleo PTP/MTP é
reutilizável, mas captura, modo remoto, eventos e propriedades ficam atrás de
um perfil por família/modelo.

## Fontes e validação

- PTP/MTP padrão para sessão, storage, objetos e transferência;
- operações e eventos Canon declarados pela câmera em `GetDeviceInfo`;
- descritores de propriedades retornados em runtime;
- implementação e base de quirks do `libgphoto2` como referência aberta;
- teste físico por modelo e firmware antes de entrar na allowlist.

Adicionar uma câmera exige registrar identificação, operações/eventos,
descritores de ISO/WB/shutter, sequência de liberação, variante de evento de
objeto e pelo menos cinco capturas/importações consecutivas sem reconexão.
