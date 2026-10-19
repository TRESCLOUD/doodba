# `trescloud-v20-production`: rama de producción de TRESCLOUD para Odoo 20.0

Este repo es un fork de [`Tecnativa/doodba`](https://github.com/Tecnativa/doodba).
Esta rama (`trescloud-v20-production`) es la referencia **congelada** desde la
que se construye la imagen real que usan los clientes de Odoo 20.0
(`patriciorangles/doodba-v20:latest`). No se vuelve a mezclar con `master` ni
con upstream — el único tipo de cambio aceptable acá es un parche de
emergencia, deliberado y documentado.

## Por qué existe esta rama (y por qué está separada de `master`)

- **`master`** sigue el upstream de Tecnativa libremente — se puede usar
  "Sync fork" de GitHub sobre esa rama cuando quieran, sin ningún riesgo,
  porque ningún cliente construye su imagen desde ahí.
- **`trescloud-v20-production`** queda fija en el estado probado y certificado
  para clientes reales. Los clientes necesitan estabilidad, no la última
  versión de todo — una vez que esta rama está certificada y corriendo, el
  valor de "quedar al día" no compensa el riesgo de romper algo que ya
  funciona.

**Nunca se usa "Sync fork" sobre esta rama.**

## El parche de Python

Ver `20.0.Dockerfile`, línea 1 en adelante, para el patrón exacto:
`ARG DOODBA_PYTHON_BASE_TAG=3.14` declarado como **primera línea del archivo**
(antes de cualquier `FROM`), usado para parametrizar
`FROM python:${DOODBA_PYTHON_BASE_TAG}-slim-bookworm AS foundation`. Es el
único cambio real de TRESCLOUD vs. el Dockerfile de Tecnativa — necesario
porque los módulos compilados con Nuitka de la localización ecuatoriana para
v20 solo cargan en Python 3.14 (confirmado contra `odoo-sh-template`, sección
"Información técnica" de su `README.md`).

El `20.0.Dockerfile` real de Tecnativa ya usa `${PYTHON_VERSION%.*}` dinámico
(la variable de entorno que trae la imagen oficial de Python) en las rutas de
`doodbalib` — no hubo que tocar nada más que el `ARG` y la línea `FROM`,
a diferencia de versiones anteriores del fork que tenían esas rutas
hardcodeadas a mano.

**Validado con build real:** Python 3.14.8, `doodbalib` en
`/usr/local/lib/python3.14/site-packages/doodbalib`, glibc 2.36 (Debian
bookworm). No se encontró ningún pin de versión adicional (como el de
`gevent` en v18) que bloquee Python 3.14 en esta versión.

## Historia de esta customización (para que no se repita el error de v18)

En la rama `trescloud-v18-production` de este mismo repo, el intento
original de parametrizar la versión de Python falló por dos razones: el
`ARG` quedó declarado dentro de un stage en vez del alcance global del
archivo, y faltaba su re-declaración tras el `FROM`. Esta rama usa desde el
principio el patrón ya corregido (alcance global, nombre propio
`DOODBA_PYTHON_BASE_TAG` que no choca con la variable `PYTHON_VERSION` de la
imagen oficial) — ver `trescloud-v18-production` para el detalle completo de
qué salió mal la primera vez.

## Segundo parche: permisos de grupo en `/opt/odoo/custom/ssh`

Línea 273-277 de `20.0.Dockerfile` (código original de Tecnativa, no
customización nuestra): `autoaggregate` (el script que corre
`invoke git-aggregate`) baja privilegios a `UID=GID=1000` (el usuario/grupo
`odoo`) antes de ejecutar `git fetch`, para que el código clonado no quede
de root. Pero el `chmod -R u=rwX,go=` dejaba las deploy keys legibles
**solo** por `root` — el grupo `odoo` (GID 1000) no tenía ningún permiso.
Resultado: en el momento exacto de clonar un repo privado por SSH, el
proceso ya no es root y no puede leer su propia llave
(`no such identity: ...: Permission denied`), fallando en silencio porque
`invoke git-aggregate` corre con reintentos que tragan el error.

Se cambió a `chmod -R u=rwX,g=rX,o=`: el grupo `odoo` gana lectura (que es
justo con quien corre el fetch), `o=` se mantiene en cero (nada cambia de
cara a terceros). Confirmado con una instalación real de punta a punta:
sin este parche, los 3 repos privados por SSH (enterprise, localización
compilada, repo de cliente) quedaban vacíos aunque el deploy se reportara
exitoso.

**Pendiente verificar:** si `18.0` tiene el mismo problema potencial. Su
`tasks.py` usa un mecanismo de aggregate distinto
(`--file setup-devel.yaml run --rm -T odoo`, sin el `autoaggregate`/baja de
privilegios), así que probablemente nunca lo expuso — no confirmado
todavía con una prueba real en esa rama.

## Cómo se certificaría una actualización de esta rama

Si algún día hace falta adoptar algo nuevo de upstream para v20:

1. Partir de `master` ya actualizado (sync libre, sin riesgo).
2. Aplicar el parche de Python de esta misma rama sobre ese estado nuevo.
3. Correr la batería de pruebas completa en un sandbox aislado: `git-aggregate`
   + `img-build` + `invoke start` + instalar módulos reales de cliente +
   confirmar que Odoo responde.
4. Solo si certifica, actualizar esta rama (o crear una nueva, según el
   alcance del cambio) — nunca un `git merge`/sync directo.

## Cómo usar esto con el instalador de TRESCLOUD

Esta rama produce la imagen base (`patriciorangles/doodba-v20:latest`, ver
`BUILDING-TRESCLOUD.md`). Para desplegar un servidor de cliente real usando
esa imagen, el proceso completo (bootstrap del servidor, deploy keys,
git-aggregate, Postgres, hardening) vive en otro repo:
[`TRESCLOUD/odoo-doodba-install-toolkit`](https://github.com/TRESCLOUD/odoo-doodba-install-toolkit).

```bash
git clone git@github.com:TRESCLOUD/odoo-doodba-install-toolkit.git
cd odoo-doodba-install-toolkit/scripts
# Editar las variables de cliente al inicio de install_all.sh
bash install_all.sh --version 20.0
```

`versions/20.0.env` de ese repo fija `PG_VERSION=18` y la versión del
template de Copier (`10.0.5`, la primera con soporte para Odoo 20.0) usados
para v20. Este repo (`doodba`) y esta rama en particular son solo la pieza
"imagen base" de ese proceso — no reemplazan al instalador ni duplican su
documentación.

El `install_all.sh` clona el repo de infraestructura del cliente, que a su
vez nace de clonar/generar con Copier
[`TRESCLOUD/odoo-infra-base-template`](https://github.com/TRESCLOUD/odoo-infra-base-template)
— ese repo trae el `odoo/Dockerfile` que hace
`FROM patriciorangles/doodba-v20:latest`, la imagen que se construye desde
esta rama. **Nota:** a diferencia de v18 (rama `18.0` real en ese repo), la
plantilla equivalente para v20 (`odoo20-base`) todavía vive solo local,
pendiente de publicarse como rama `20.0` ahí.

**Los 3 repos, en orden de uso:**

1. **`doodba`** (este repo, esta rama) → produce la imagen base.
2. **`odoo-infra-base-template`** → la plantilla del proyecto Doodba que
   referencia esa imagen; se clona/genera una vez por cliente.
3. **`odoo-doodba-install-toolkit`** → orquesta el deploy completo en el
   servidor del cliente, usando lo que generan los dos anteriores.
