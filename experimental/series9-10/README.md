# Series 9 y Series 10 — EXPERIMENTAL

Estado: candidato sin validación en relojes físicos Series 9 o Series 10. Este apartado conserva la investigación, el código disponible y las pruebas reproducibles. No declara la app universal.

## Descargas

- [IPA candidato experimental](Readiness-Series9-10-EXPERIMENTAL.ipa?raw=true).
- [Kit completo de fuentes y pruebas](Readiness-Series9-10-Experimental-Kit.zip?raw=true).
- [Resultado de validación](validation.json).
- [Auditoría de dependencias](DEPENDENCIES.md).

El IPA es exactamente el build42 ya respaldado, presentado aquí como candidato para Series 9/10. No se ha modificado el motor para fingir compatibilidad: no se encontró un bloqueo por Series 11 en las fuentes disponibles. Su SHA-256 es `e75de7151ad544abd73da0345a9696e00d463e38abf2eb1738fd2acc402ad2de`.

## Resultado observado

Las 53 comprobaciones pasaron en el Mac y en los simuladores Series 9 (41 mm) y Series 10 (46 mm), ambos con watchOS 27.2. También pasaron 11 comprobaciones del inspector del paquete. Ninguna de estas pruebas confirma el funcionamiento de la app completa en un reloj físico Series 9/10.

## Qué se puede probar

El proyecto `ExperimentalHarness.xcodeproj` ejecuta únicamente pruebas sintéticas de nuestro código, sin leer ni escribir HealthKit. No incluye la interfaz de Cobalt y no sustituye la app del reloj. Seleccionar el esquema `SimulatorHarness` y un simulador Series 9 o Series 10 con watchOS 27.2 y pulsar Run.

El resultado esperado es 53 comprobaciones: 25 de regresión del motor, 12 de actividad y 16 de aceptación/rechazo de fuentes de los ocho identificadores representados en los perfiles de Xcode para estos modelos. Los identificadores son entradas sintéticas; no emulan sus sensores ni sus chips.

Para ejecutar las mismas comprobaciones en el Mac:

```sh
./test-host.sh
```

Para revisar el candidato sin instalarlo:

```sh
python3 inspect-candidate.py Readiness-Series9-10-EXPERIMENTAL.ipa --model Watch7,3 --watchos 27.3
```

Un informe `packageAuditPassed: true` valida el paquete conocido, no su funcionamiento físico. El inspector mantiene `physicalWatchCompatibilityVerified: false` y rechaza paquetes cambiados, modelos fuera de alcance y watchOS inferior a 27.3.

## Requisitos y límites del candidato

- Es un paquete para reloj físico; no se instala en el simulador. El ejecutable recuperado exige watchOS 27.3. La única validación del paquete completo es Series 11 con 27.3 beta 2, build 24S5296d. Otras versiones o builds no se consideran verificadas.
- Requiere firma de desarrollo y perfil propios, con el identificador `cl.moisesretamal.ReadinessAuthenticUIProbe.watchkitapp` y HealthKit público. Consultar también las [notas de firma del respaldo](../../backups/build38/README.md).
- La interfaz y el puente de Cobalt dependen de APIs privadas y de un binario concreto. No basta con cambiar su versión mínima ni sus identificadores. El runtime local de simulador solo contiene recursos de Cobalt, sin su ejecutable.
- No se ha probado la instalación, lectura de sensores, sincronización, detalles de las tarjetas ni actualización de fondo en Series 9/10 físicos.
- Las fuentes del motor proceden del build30 recuperado; las del adaptador de Fitness son las del build42. No disponemos del código completo del puente build38. El binario preserva ese puente.

## Prueba física pendiente

Con un participante que disponga de esos relojes: registrar modelo y build exacto de watchOS, comprobar firma e instalación, abrir la app, autorizar solo las lecturas necesarias y verificar que el resultado use registros actuales. Comprobar Vitals, Sleep y Fitness con y sin historial suficiente, reiniciar la app y revisar la actualización del día siguiente. Informar únicamente el estado y errores técnicos; no publicar contenedores ni datos personales de salud.

## Archivos

`Engine/`, `FitnessAdapter/` y `Tests/` contienen las fuentes disponibles. `SimulatorHarness/` es una interfaz de pruebas separada; su unidad Swift incluye copias de las fuentes y comprobaciones para que el proyecto abra sin dependencias externas. `models.json` procede de los perfiles de dispositivos de Xcode local. Después de modificar las fuentes modulares, ejecutar `python3 generate-harness.py` para regenerar esa unidad antes de volver a ejecutar el proyecto.
