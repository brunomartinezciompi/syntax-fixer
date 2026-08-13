# SyntaxFixer

Un panel flotante y minúsculo para macOS que corrige la gramática y la sintaxis de una frase y te la deja **copiada en el portapapeles**. Sin ventana de navegador, sin pestañas, sin salir de lo que estás haciendo.

```
┌──────────────────────────────┐
│ ●  syntax          copiado ✓ │
├──────────────────────────────┤
│ ❯ this dont read good        │
├──────────────────────────────┤
│ ✓ This doesn't read well.    │
├──────────────────────────────┤
│ [ Validar ⌘↵ ]  [ Clear ⌘K ] │
└──────────────────────────────┘
```

- Siempre encima de las demás ventanas, en todos los escritorios.
- Se arrastra desde cualquier parte del fondo y recuerda dónde lo dejaste.
- La ventana crece sola si la respuesta es larga.
- Sin icono en el Dock mientras corre (es una app tipo agente), pero con un lanzador fijo si la agregás al Dock.

## Requisitos

- macOS 14 o superior.
- Las Command Line Tools de Xcode (`xcode-select --install`) para compilar.
- **[Claude Code](https://claude.com/claude-code) instalado y con sesión iniciada** (`claude` en el `PATH`).

## Cómo funciona la integración con Claude

**No hay ninguna API key en este repositorio, ni en el código, ni en el binario.** La app no maneja credenciales en absoluto.

Lo que hace es ejecutar el binario `claude` que ya tenés instalado y autenticado en tu máquina, y le pasa el texto por `stdin`:

```
claude -p --model sonnet --output-format text \
  --setting-sources "" --strict-mcp-config \
  --system-prompt "<instrucciones de reescritura>" \
  "<tarea>"
```

La autenticación es asunto del CLI: vive en el llavero de macOS, la gestiona Claude Code y la app nunca la ve ni la toca. Si usás Claude Code con una suscripción, esto consume esa suscripción; si lo usás con una API key propia, consume esa. En ambos casos la app es indiferente.

Tres detalles que importan:

- **`--setting-sources ""`** — sin esto, el CLI carga tu configuración global (incluido `CLAUDE.md`) y contamina la respuesta: te devuelve el texto con un preámbulo tipo "¡Acá está tu texto corregido:" o traducido al idioma que tengas configurado. Con esto, la salida es sólo el texto corregido.
- **`--system-prompt`** reemplaza el system prompt por completo (no lo agrega), y el proceso corre con el directorio de trabajo en una carpeta temporal vacía, para que no cargue el `CLAUDE.md` de ningún proyecto.
- **El binario se busca por rutas conocidas** (Homebrew, `~/.claude/local`, `~/.local/bin`, …) porque una app lanzada desde Finder no hereda el `PATH` de tu shell.

Sobre velocidad: la llamada tarda ~6-9 segundos, y casi todo es el arranque del CLI, no el modelo. Probado con `haiku` en lugar de `sonnet`, y quitando herramientas y secciones dinámicas del prompt: no cambia el tiempo (y sacar las secciones dinámicas empeora el resultado). Si querés que sea instantáneo, hay que ir contra la API directo con una key, que es otro modelo de uso.

## Compilar e instalar

```bash
./build.sh                                    # genera build/SyntaxFixer.app
cp -R build/SyntaxFixer.app /Applications/
```

No necesita Xcode ni un `.xcodeproj`: `build.sh` compila con `swiftc`, genera el icono, arma el bundle y lo firma ad-hoc (sin la firma, macOS mata la app al abrirla desde Finder).

Para tener un lanzador fijo en el Dock, arrastrá `/Applications/SyntaxFixer.app` al Dock. Como es una app tipo agente, el click abre el panel; si ya está corriendo, lo trae al frente.

## Uso

| Acción | Atajo |
|---|---|
| Corregir el texto | `⌘↵` o botón **Validar** |
| Limpiar todo | `⌘K` o botón **Clear** |
| Copiar el resultado de nuevo | click sobre el resultado |
| Cerrar la app | `⌘Q` o la `×` |

El resultado se copia al portapapeles automáticamente en cuanto llega.

## Estructura

| Archivo | Qué hace |
|---|---|
| `Sources/main.swift` | El `NSPanel` flotante, el ciclo de vida de la app y el ajuste de alto |
| `Sources/ContentView.swift` | La interfaz en SwiftUI y el estado |
| `Sources/ClaudeRunner.swift` | Localiza y ejecuta el CLI `claude` |
| `make-icon.swift` | Dibuja el icono en los 10 tamaños que pide `iconutil` |
| `build.sh` | Compila y arma el `.app` |

Si algo se comporta raro, la app escribe un log en `~/Library/Logs/SyntaxFixer.log`.

## Licencia

MIT
