# Build y publicación de la imagen propia de TRESCLOUD

Este fork (`TRESCLOUD/doodba`) existe para una sola customización deliberada sobre
el Dockerfile oficial de Tecnativa por versión de Odoo: **fijar la versión de
Python** que usa Doodba, porque los módulos compilados con Nuitka de TRESCLOUD
solo cargan en la versión de Python exacta con la que se compilaron (ver
`l10n_ec`/apps TRESCLOUD en `trescloud-modules/odoo-ecuador-<version>`).

**Importante:** desde octubre 2026 este repo usa ramas de producción congeladas
por versión (`trescloud-<version>-production`) en vez de editar `master`
directo — ver `TRESCLOUD-PRODUCTION-BRANCH.md` para el porqué. Todo build real
se hace parado en la rama congelada correspondiente, nunca en `master`.

No hay CI/CD ni Jenkinsfile para este build — hasta ahora siempre se hizo a mano.
Si se automatiza después (Jenkins, GitHub Actions), actualizar aquí la
referencia, no borrarlo.

## Qué se customiza

Rama: `trescloud-v18-production`. Único cambio real vs. el Dockerfile de
`Tecnativa/doodba`: `ARG DOODBA_PYTHON_BASE_TAG=3.12` parametrizando el
`FROM` (default 3.12; solo validado en ese valor, ver limitación en
`TRESCLOUD-PRODUCTION-BRANCH.md`). Imagen publicada: `patriciorangles/doodba-v18:latest`.

## Build local + publicación

Parado en la rama de producción de la versión que corresponda (ej.
`git checkout trescloud-v18-production`):

```bash
# Build (el stage final, "onbuild", es el que usan los Dockerfile de los clientes
# con "FROM patriciorangles/doodba-v<version>:latest")
docker build -f 18.0.Dockerfile --target onbuild -t patriciorangles/doodba-v18:latest .

# Para construir con otra versión de Python (solo si esa rama ya lo soporta
# y fue probada — ver limitación de v18 arriba):
# docker build -f 18.0.Dockerfile --target onbuild \
#   --build-arg DOODBA_PYTHON_BASE_TAG=3.14 -t patriciorangles/doodba-v18:latest .

# Login (una sola vez por máquina)
docker login -u patriciorangles

# Publicar
docker push patriciorangles/doodba-v18:latest
```

Para otra versión de Odoo, cambiar de rama (`git checkout trescloud-v<version>-production`)
y el tag `doodba-v18` → `doodba-v<version>`.

## Antes de publicar una versión nueva

1. Confirmar que la versión de Python elegida es la que exige la localización
   compilada de esa versión (ver `odoo-sh-template`, sección "Información
   técnica" del `README.md`, o preguntar directo).
2. Hacer un build de prueba local y confirmar que compilan las dependencias C
   (psycopg2, lxml, gevent, python-ldap, cryptography, pycairo) sin errores —
   incluyendo cualquier pin de versión específico que tenga esa rama (ej. el
   de gevent en v18, ver `TRESCLOUD-PRODUCTION-BRANCH.md`).
3. Seguir el proceso de certificación completo de `TRESCLOUD-PRODUCTION-BRANCH.md`
   (sandbox + pruebas reales) antes de reemplazar lo que usan los clientes.
4. Solo entonces hacer `docker push`.
