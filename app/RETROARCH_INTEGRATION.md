# RetroBox: interfaz sencilla sobre RetroArch
Esta compilación es una prueba de integración, NO una distribución comercial aprobada.
El motor es RetroArch 1.22.2. No usa el reproductor FFI experimental anterior.
Solo NES/Contra en el RetroArch original ha sido confirmado por Roberto; esta interfaz y las otras consolas requieren prueba real.

## Uso
Extraer TODO el ZIP y abrir retrobox.exe. Importar un juego (ROM suelta) o un ZIP de biblioteca.
Abrir consola y tocar juego: RetroBox selecciona su core automáticamente.
Esc, o Select + abajo, cierra el motor limpiamente y devuelve la biblioteca.
F2 guarda estado y F4 carga estado. F1 abre el menú avanzado.
El motor conserva su propia ventana de juego; la biblioteca permanece abierta detrás.
Motores e imagen permite importar DLL de cores x64 por consola y elegir suavizado.
Los cores son código nativo: importa únicamente archivos de una fuente de confianza.
Si el motor no está incluido, elegir retroarch.exe una sola vez en la pantalla del juego.
Guardados, estados, BIOS, configuración y registro se conservan en Documentos/RetroBoxLibrary.
No borrar ni cerrar por la fuerza la ventana mientras guarda.
Los perfiles SDL2 incluyen Nintendo Switch Pro Controller; probar el mando real sigue pendiente.
No se incluyen ROMs ni BIOS.

## Tamaño y licencias
Se eliminan bases de datos, temas, shaders, overlays y herramientas de depuración.
El tamaño real queda en PACKAGE-SIZE.txt; no se promete una cifra sin medir.
Selección: Stella (GPLv2), FCEUmm (GPLv2), bsnes (GPLv3), BlastEm (GPLv3), MAME (GPLv2+), según libretro-core-info.
Se reemplazan Snes9x2010, Genesis Plus GX y FBNeo para evitar restricciones no comerciales.
El usuario solo ha probado NES con FCEUmm; los otros cores seleccionados aún requieren pruebas reales.
MAME puede aumentar considerablemente el tamaño y exige ROM sets compatibles.
NO añadir cobros, licencias Turbify o Microsoft Billing a este paquete de prueba.
RetroArch y los cores conservan sus licencias propias. Una versión comercial necesita inventario,
avisos y código fuente correspondiente de cada binario; este artefacto no cumple aún esa entrega.

## Validación pendiente
Jugar, salir y abrir otro juego sin elegir cores; verificar sonido, mando y guardado en cada consola.
Escalado conserva proporción y permite suavizado, pero no aumenta el detalle de la ROM.
Arcade requiere ROM sets compatibles con su core y, en algunos casos, BIOS correspondientes.
