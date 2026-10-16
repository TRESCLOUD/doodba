# Ramas de producción de TRESCLOUD

Este repo es un fork de [`Tecnativa/doodba`](https://github.com/Tecnativa/doodba).
Antes de octubre 2026, TRESCLOUD editaba directo `18.0.Dockerfile` en `master`
para fijar la versión de Python, lo cual dejó a `master` divergido y volvió
riesgoso cualquier intento de traer actualizaciones de upstream (ver
sección "Qué pasó antes" más abajo). Esta es la estrategia que lo reemplaza.

## La estrategia

- **`master`** sigue el upstream de Tecnativa **libremente**. Se puede usar
  "Sync fork" de GitHub sobre esta rama en cualquier momento, sin riesgo —
  ningún cliente construye su imagen desde `master`. Es terreno de evaluación:
  sirve para ver qué trae Tecnativa de nuevo antes de decidir si conviene
  adoptarlo.
- **`trescloud-<version>-production`** (ej. `trescloud-v18-production`) es una
  rama **congelada**: captura el estado exacto, probado y en uso por clientes
  reales, de una versión de Odoo. No se vuelve a mezclar con `master` ni con
  upstream — nunca. El único tipo de cambio aceptable ahí es un parche de
  emergencia, deliberado y documentado.
- Cada imagen que se publica a Docker Hub (`patriciorangles/doodba-v<version>`)
  se construye **desde su rama congelada correspondiente**, nunca desde `master`.

## Por qué existe esta separación

1. **Upstream cambia de forma importante y constante.** Entre que este fork
   divergió y hoy, Tecnativa reestructuró `18.0.Dockerfile` por completo (de
   single-stage a multi-stage, con cache mounts de BuildKit, nuevos pines de
   `setuptools`/`flanker`, etc. — 20+ commits solo en ese archivo). Sincronizar
   a ciegas sobre una rama que clientes reales están usando es un riesgo que
   no vale la pena correr sin probarlo primero.
2. **Los clientes necesitan estabilidad, no la última versión de todo.** Una
   vez que una versión está certificada y corriendo, el valor de "quedar al
   día" no compensa el riesgo de romper algo que ya funciona.
3. **El único cambio real de TRESCLOUD es la versión de Python**, y es
   intencional que viva como una diferencia permanente y documentada contra
   upstream en la rama congelada — no algo que haya que "resolver" en cada
   sync.

## Cómo se certifica una versión nueva

Cuando haga falta adoptar algo nuevo de upstream (por ejemplo, evaluar la
estructura multi-stage para v18, o certificar v20):

1. Partir de `master` ya actualizado (sync libre, sin riesgo).
2. Aplicar el parche de Python (ver `BUILDING-TRESCLOUD.md`).
3. Correr la batería de pruebas completa en un sandbox aislado: `git-aggregate`
   + `img-build` + `invoke start` + instalar módulos reales de cliente +
   confirmar que Odoo responde. (Así se validó v20 antes de este documento.)
4. Solo si certifica, crear la rama `trescloud-<version>-production` nueva
   desde ese estado. La rama anterior de esa misma versión de Odoo (si existe)
   queda intacta, sirviendo a los clientes que ya están ahí.

**Nunca se usa "Sync fork" sobre una rama `trescloud-*-production`.**

## El parche de Python: cómo quedó y por qué se rompió antes

Ver `18.0.Dockerfile`, línea 1 en adelante, para el patrón exacto:
`ARG DOODBA_PYTHON_BASE_TAG=3.12` declarado como **primera línea del archivo**
(antes de cualquier `FROM`), usado para parametrizar
`FROM python:${DOODBA_PYTHON_BASE_TAG}-slim-bookworm`.

El intento anterior (commits `0ef04c7`..`aef980b`, ya en `master`) falló por
dos razones reales, confirmadas al revisar el diff y con una prueba real:

1. El `ARG` quedó declarado **dentro de un stage** (después de un `FROM`
   anterior), no en el alcance global del archivo completo — Docker solo
   permite parametrizar un `FROM` con `ARG`s declarados antes del *primer*
   `FROM` de todo el archivo.
2. Faltaba la re-declaración de `ARG` después del propio `FROM`, necesaria
   para poder seguir usando su valor en `RUN`/`COPY` posteriores dentro de
   esa etapa.

Por eso se terminó fijando todo a mano (`aef980b`). La corrección usa un
nombre de variable propio (`DOODBA_PYTHON_BASE_TAG`, no `PYTHON_VERSION`) para
no chocar con la variable de entorno del mismo nombre que ya trae la imagen
oficial de Python — y la declara en el lugar correcto.

**Limitación confirmada:** esta rama (`trescloud-v18-production`) solo está
probada y validada con el default (Python 3.12). Hay otro pin de versión
específico más abajo en el Dockerfile (`gevent==23.9.1`/`greenlet==3.0.3`,
puesto "para compatibilidad con 3.12") que no compila contra Python 3.14 —
confirmado con un build real. Cambiar `DOODBA_PYTHON_BASE_TAG` en esta rama
no alcanza para correr v18 en otra versión de Python sin revisar también ese
pin. Para v20 (que sí necesita 3.14) no aplica este problema porque su
`requirements.txt` no tiene ese `sed`/pin manual.

## Qué pasó antes (para que no se repita)

`master` tiene 4 commits propios (`0ef04c7`, `723b832`, `acf2d64`, `aef980b`)
que editan `18.0.Dockerfile` directo — el origen de la divergencia que generó
todo este problema. Esos commits siguen en el historial de `master` (no se
reescribe), pero `master` ya no se usa para construir ninguna imagen real;
`trescloud-v18-production` es la que cuenta a partir de ahora.
