# Auditoría de compatibilidad

| Componente | Hallazgo | Consecuencia |
|---|---|---|
| Motor público disponible (build30) | Usa Foundation/HealthKit; no exige un identificador de Series 11 | Puede compilarse y probarse por separado; no prueba el puente binario actual |
| Filtro de fuentes | Prefijo `watch`, fuente `com.apple.health.*`, entrada no manual | Los ocho identificadores de Series 9/10 de Xcode pasan; las entradas manuales se rechazan |
| Señales opcionales | Temperatura, respiración y oxígeno pueden faltar | El caso de regresión básico obtiene resultado con sueño, RMSSD y pulso de reposo sintéticos |
| Fitness build42 | Resúmenes públicos de actividad, ayer observado y al menos cinco días de referencia | Sin condición de modelo; la disponibilidad real requiere registros autorizados |
| Cobalt + puente recuperado | Alias Swift, direcciones del binario, identidad del bundle y APIs privadas | Dependencia de versión/ABI; no se puede declarar universal ni recompilar todo desde las fuentes disponibles |
| Corrección de direcciones build42 | Resuelve el desplazamiento del ejecutable por su encabezado Mach-O | Evita asumir que la imagen cero de dyld es Cobalt; no valida todos los puntos de enganche |
| Arquitectura del paquete | Los tres ejecutables son arm64e, subtipo `0x80000002`; plataforma watchOS física | No es una compilación de simulador; no se encontró subtipo arm64e.x1 en estos encabezados |
| Versión | Cobalt y Fit requieren 27.3; puente 27.2 | El paquete completo requiere al menos 27.3; única prueba física en Series 11/27.3 beta2 |

Apple documenta ARM64 para Series 9 y posteriores desde watchOS26: [WWDC25](https://developer.apple.com/videos/play/wwdc2025/334/). También documenta el soporte de autenticación de punteros y distingue arm64e.x1 en chips recientes: [Pointer authentication](https://developer.apple.com/documentation/security/preparing-your-app-to-work-with-pointer-authentication). Estos datos justifican investigar la compatibilidad; no equivalen a una prueba de este paquete.

No se eliminaron controles de integridad ni se bajó artificialmente el deployment target. La revisión no encontró un bloqueo por Series 11 que fuera necesario quitar en las fuentes disponibles. La investigación conserva el candidato conocido y añade un banco de pruebas independiente y un inspector que no confunde integridad del paquete con compatibilidad física.
