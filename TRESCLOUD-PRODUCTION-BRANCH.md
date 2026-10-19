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

## Segundo parche: permisos de las deploy keys SSH (5 intentos, causa real encontrada leyendo el código fuente de Doodba)

**Por qué hace falta este parche en absoluto:** Doodba, por diseño, no
espera que un proyecto guarde llaves SSH privadas como archivo dentro del
repo. Su mecanismo nativo para que `devel-setup`/`autoaggregate` clone
repos privados es **reenvío del agente SSH del operador humano**
(`SSH_AUTH_SOCK`) — de hecho `devel-setup` en `devel.yaml` sobreescribe
sus volúmenes para NO montar `/opt/odoo/custom/ssh` en absoluto, solo
`/opt/odoo/custom/src`. TRESCLOUD usa en cambio 3 deploy keys fijas por
proyecto, guardadas en el repo, registradas en GitHub como solo lectura
(ver D7/D8 del documento de decisiones de arquitectura — esto es
deliberado y, por diseño, más seguro que reenviar el agente completo del
operador: una deploy key solo puede leer un repo; un agente reenviado
normalmente tiene acceso de lectura/escritura a muchos más). Ese es el
costo que hay que seguir pagando: hacer manualmente lo que Doodba no
necesita resolver en su propio diseño.

Como las llaves llegan por `COPY --chown=root:odoo` (línea 269,
`ONBUILD COPY $LOCAL_CUSTOM_DIR /opt/odoo/custom`) y `autoaggregate` baja
privilegios a `UID=GID=1000` (usuario `odoo`) antes de hacer `git fetch`,
el proceso sin privilegios de root no podía leer su propia llave
(`no such identity: ...: Permission denied`) — fallando en silencio
porque `invoke git-aggregate` corre con reintentos que tragan el error.

**Intento 1 (incorrecto):** dar lectura al grupo `odoo`
(`chmod -R u=rwX,g=rX,o=`). Falló: OpenSSH rechaza *cualquier* permiso de
grupo sobre una llave privada sin importar cuál grupo sea
(`Permissions 0640 ... are too open`) — chequeo estricto de que el
archivo no tenga bits de grupo/otros en absoluto.

**Intento 2 (incorrecto):** `chown -R ${UID}:${GID}` a **todo** el
directorio `/opt/odoo/custom/ssh`. Las llaves quedaron legibles, pero
también cambió el dueño de `config`/`known_hosts`, y `autoaggregate`
sigue usando `$HOME=/root` incluso tras bajar a UID 1000 (no cambia
`$HOME` al hacer `setuid`), así que SSH resuelve `~/.ssh/config` →
`/root/.ssh/config` (el symlink). OpenSSH exige que ese archivo sea de
`root` o del UID que invoca — con dueño `1000` falló con
`Bad owner or permissions on /root/.ssh/config`.

**Intento 3 (parecía funcionar, en realidad no):** `chown ${UID}:${GID}`
**solo** a los archivos `deploy_key_*` (no `.pub`, no `config`, no
`known_hosts`). Un diagnóstico insertado justo después del `chown`
mostraba el resultado correcto. **Pero no servía en la imagen final:**
`/opt/odoo/common/build.d/800-permissions` (script propio de Doodba, no
nuestro, que corre sin condición alguna al final de cada build vía
`/opt/odoo/common/build`) hace, entre otras cosas:

```python
# Revierte a root:odoo cualquier archivo bajo /opt/odoo que no lo sea
# ya (excepto symlinks) — SIN excepción para /opt/odoo/custom/ssh
find /opt/odoo (-not -user root -or -not -group odoo) -not -type l \
  | xargs chown root:odoo
```

Esto corre **después** de nuestro `chown` (está en un `ONBUILD RUN`
posterior en el Dockerfile), así que revertía el resultado sin que el
diagnóstico — ubicado antes de ese paso — lo notara. Encontrado releyendo
el código fuente real de Doodba, no por prueba y error.

**Intento 4 (incorrecto, por un detalle más sutil):** el mismo script
`800-permissions` sí tiene una excepción explícita — si existe
`/home/odoo/.ssh` como directorio, lo **chownea a `odoo:odoo`** sin
tocar nada bajo `/opt/odoo`. Se intentó aprovechar esa excepción con un
enlace simbólico (`ln -s /opt/odoo/custom/ssh /home/odoo/.ssh`). Falló
igual: `800-permissions` ejecuta `chown -R odoo:odoo /home/odoo/.ssh`
**sin `-H`**, y GNU coreutils con `-R` sin `-H`/`-L` usa por defecto
`-P` — nunca sigue symlinks, **ni siquiera cuando el symlink es el
propio argumento de la línea de comandos**. Confirmado en vivo dentro de
un contenedor: `chown -R` sobre el symlink no tocaba el directorio real;
el mismo comando con `-RH` sí. Como Doodba no usa `-H`, su propia
excepción para `/home/odoo/.ssh` nunca tenía efecto con un symlink de
por medio.

**Fix correcto (intento 5, el que quedó):** copiar (no enlazar) las
llaves físicamente a `/home/odoo/.ssh`, como directorio real e
independiente, y hacer el `chown` ahí mismo en nuestro propio paso del
Dockerfile:

```dockerfile
ONBUILD RUN [ -d ~root/.ssh ] && rm -r ~root/.ssh; \
            mkdir -p /opt/odoo/custom/ssh \
            && ln -s /opt/odoo/custom/ssh ~root/.ssh \
            && rm -rf /home/odoo/.ssh \
            && cp -a /opt/odoo/custom/ssh /home/odoo/.ssh \
            && chown -R odoo:odoo /home/odoo/.ssh \
            && chmod -R u=rwX,go= /opt/odoo/custom/ssh /home/odoo/.ssh \
            && sync
```

Al ser una copia física (no symlink), cuando `800-permissions` corre más
adelante: su primer bloque revierte `/opt/odoo/custom/ssh` a
`root:odoo` (sin problema — ese path ya no es el que se usa para
autenticar), y su excepción para `/home/odoo/.ssh` sí logra confirmarlo
como `odoo:odoo`, porque ya no hay ningún symlink que el `chown -R` (sin
`-H`) necesite atravesar. Resultado: dos copias de las llaves en la
imagen (una sin uso real en `/opt/odoo/custom/ssh`, la real en
`/home/odoo/.ssh`) — duplicación aceptable, son de solo lectura y ya
están horneadas en la imagen de cualquier forma.

**Cambio correspondiente en `ssh/config`** (repo `odoo-infra-base-template`,
rama `20.0`): las 3 rutas `IdentityFile` pasaron de
`/opt/odoo/custom/ssh/deploy_key_*` a `/home/odoo/.ssh/deploy_key_*` —
que resulta ser la misma convención que ya usa correctamente la plantilla
real de producción de `18.0`. Un ajuste anterior de este pipeline que
"corrigió" esa ruta hacia `/opt/odoo/custom/ssh` (razonando que era más
"físicamente correcta") fue, en realidad, el error que generó buena parte
de esta investigación.

Confirmado con una instalación real de punta a punta en un servidor EC2
de pruebas dedicado: los 3 repos privados por SSH (enterprise — 891
módulos, localización compilada, repo de cliente) se clonaron
correctamente, confirmado contando archivos reales en disco después de la
corrida.

Ver también el documento `01-decisiones-arquitectura-v20.docx` (decisión
D8) para el argumento completo de por qué el enfoque de TRESCLOUD
(deploy keys fijas de solo lectura) es, por diseño, más seguro que el
mecanismo nativo de Doodba (agente SSH reenviado).

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
