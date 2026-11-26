## Sincronización con Drive (obligatorio)
Carpeta Drive de este repo: "Instalacion de servidores con Doodba a partir de V18"/doodba/
https://drive.google.com/drive/folders/1eIzH99h-Dx1zxeWKepnrOWbbq1XKt4uz

Al iniciar cada sesión:
1. git pull.
2. Lee HANDOFF.md de esa carpeta ANTES de cualquier otra cosa.
3. Lee STATUS.md y DECISIONS.md.
4. Marca EN CURSO los ítems que tomes; BLOQUEADO con pregunta si son ambiguos.

Al cerrar cada sesión:
1. Commit y push citando el ID del ítem (H-0001: ...).
2. HANDOFF.md: marca HECHO con fecha y responde con commit y resultado.
3. CHANGELOG.md: entrada nueva arriba.
4. STATUS.md: reescríbelo.
5. docs/: actualiza procesos o manuales afectados.

Reglas: este repo (ramas trescloud-vXX-production) es la verdad del código; Drive, de la documentación.
No borres ítems de HANDOFF ni reescribas DECISIONS.
Nota: la rama `master` sigue al upstream Tecnativa/doodba — este archivo vive solo en las ramas de producción TRESCLOUD (`trescloud-v20-production`, `trescloud-v18-production`), no en `master`.
Guía completa: carpeta raíz de Drive, README.md.
