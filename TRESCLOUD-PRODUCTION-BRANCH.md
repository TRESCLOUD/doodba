# `trescloud-v18-production`: rama de producción de TRESCLOUD para Odoo 18.0

Este repo es un fork de [`Tecnativa/doodba`](https://github.com/Tecnativa/doodba).
Esta rama (`trescloud-v18-production`) es la referencia **congelada** desde la
que se construye la imagen real que usan los clientes de Odoo 18.0
(`patriciorangles/doodba-v18:latest`). No se vuelve a mezclar con `master` ni
con upstream — el único tipo de cambio aceptable acá es un parche de
emergencia, deliberado y documentado.

## Por qué existe esta rama (y por qué está separada de `master`)

Antes de octubre 2026, TRESCLOUD editaba directo `18.0.Dockerfile` en `master`
para fijar la versión de Python. Eso dejó a `master` divergido de Tecnativa, y
cualquier intento de traer actualizaciones de upstream se volvía riesgoso: el
`18.0.Dockerfile` real de Tecnativa cambió muchísimo desde entonces (pasó de
single-stage a multi-stage, con cache mounts de BuildKit, nuevos pines de
`setuptools`/`flanker`, etc. — 20+ commits solo en ese archivo), así que
sincronizar a ciegas sobre una rama que clientes reales están usando no valía
la pena sin probarlo primero (ver "Qué pasó antes" más abajo).

Con esta separación:

- **`master`** sigue el upstream de Tecnativa libremente — se puede usar
  "Sync fork" de GitHub sobre esa rama cuando quieran, sin ningún riesgo,
  porque ningún cliente construye su imagen desde ahí.
- **`trescloud-v18-production`** queda fija en el estado probado y en uso real
  por los clientes. Los clientes necesitan estabilidad, no la última versión
  de todo — una vez que esta rama está certificada y corriendo, el valor de
  "quedar al día" no compensa el riesgo de romper algo que ya funciona.

**Nunca se usa "Sync fork" sobre esta rama.**

## El parche de Python: cómo quedó y por qué se rompió antes

Ver `18.0.Dockerfile`, línea 1 en adelante, para el patrón exacto:
`ARG DOODBA_PYTHON_BASE_TAG=3.12` declarado como **primera línea del archivo**
(antes de cualquier `FROM`), usado para parametrizar
`FROM python:${DOODBA_PYTHON_BASE_TAG}-slim-bookworm`. Es el único cambio real
de TRESCLOUD vs. el Dockerfile de Tecnativa — necesario porque los módulos
compilados con Nuitka de la localización ecuatoriana solo cargan en la
versión de Python exacta con la que se compilaron.

El intento anterior (commits `0ef04c7`..`aef980b`, hoy solo en el historial
viejo de `master`) falló por dos razones reales, confirmadas al revisar el
diff y con una prueba real:

1. El `ARG` quedó declarado **dentro de un stage** (después de un `FROM`
   anterior), no en el alcance global del archivo completo — Docker solo
   permite parametrizar un `FROM` con `ARG`s declarados antes del *primer*
   `FROM` de todo el archivo.
2. Faltaba la re-declaración de `ARG` después del propio `FROM`, necesaria
   para poder seguir usando su valor en `RUN`/`COPY` posteriores dentro de
   esa etapa.

Por eso se terminó fijando todo a mano. La corrección de esta rama usa un
nombre de variable propio (`DOODBA_PYTHON_BASE_TAG`, no `PYTHON_VERSION`) para
no chocar con la variable de entorno del mismo nombre que ya trae la imagen
oficial de Python — y la declara en el lugar correcto.

**Limitación confirmada:** esta rama solo está probada y validada con el
default (Python 3.12). Hay otro pin de versión específico más abajo en el
Dockerfile (`gevent==23.9.1`/`greenlet==3.0.3`, puesto "para compatibilidad
con 3.12") que no compila contra Python 3.14 — confirmado con un build real.
Cambiar `DOODBA_PYTHON_BASE_TAG` en esta rama no alcanza para correr v18 en
otra versión de Python sin revisar también ese pin.

## Cómo se certificaría una actualización de esta rama

Si algún día hace falta adoptar algo nuevo de upstream para v18 (por ejemplo,
la estructura multi-stage que Tecnativa ya tiene):

1. Partir de `master` ya actualizado (sync libre, sin riesgo).
2. Aplicar el parche de Python de esta misma rama sobre ese estado nuevo.
3. Correr la batería de pruebas completa en un sandbox aislado: `git-aggregate`
   + `img-build` + `invoke start` + instalar módulos reales de cliente +
   confirmar que Odoo responde.
4. Solo si certifica, actualizar esta rama (o crear una nueva, según el
   alcance del cambio) — nunca un `git merge`/sync directo.

## Qué pasó antes (para que no se repita)

`master` tenía 4 commits propios (`0ef04c7`, `723b832`, `acf2d64`, `aef980b`)
que editaban `18.0.Dockerfile` directo — el origen de la divergencia que
generó todo este problema. Esos commits ya no están en `master` (se
descartaron con un reset + force-push, una vez que su contenido quedó
rescatado y corregido en esta rama); `master` hoy es un espejo limpio de
Tecnativa.

## Cómo usar esto con el instalador de TRESCLOUD

Esta rama produce la imagen base (`patriciorangles/doodba-v18:latest`, ver
`BUILDING-TRESCLOUD.md`). Para desplegar un servidor de cliente real usando
esa imagen, el proceso completo (bootstrap del servidor, deploy keys,
git-aggregate, Postgres, hardening) vive en otro repo:
[`TRESCLOUD/odoo-doodba-install-toolkit`](https://github.com/TRESCLOUD/odoo-doodba-install-toolkit).

```bash
git clone git@github.com:TRESCLOUD/odoo-doodba-install-toolkit.git
cd odoo-doodba-install-toolkit/scripts
# Editar las variables de cliente al inicio de install_all.sh
bash install_all.sh --version 18.0
```

`versions/18.0.env` de ese repo fija `PG_VERSION` y la versión del template de
Copier usados para v18. Este repo (`doodba`) y esa rama en particular son solo
la pieza "imagen base" de ese proceso — no reemplazan al instalador ni
duplican su documentación.

El `install_all.sh` clona el repo de infraestructura del cliente (`<cliente>_infra`),
que a su vez nace de clonar/generar con Copier
[`TRESCLOUD/odoo-infra-base-template`](https://github.com/TRESCLOUD/odoo-infra-base-template)
(rama `18.0`) — ese repo trae el `odoo/Dockerfile` que hace
`FROM patriciorangles/doodba-v18:latest`, la imagen que se construye desde
esta rama.

**Los 3 repos, en orden de uso:**

1. **`doodba`** (este repo, esta rama) → produce la imagen base.
2. **`odoo-infra-base-template`** → la plantilla del proyecto Doodba que
   referencia esa imagen; se clona/genera una vez por cliente.
3. **`odoo-doodba-install-toolkit`** → orquesta el deploy completo en el
   servidor del cliente, usando lo que generan los dos anteriores.
