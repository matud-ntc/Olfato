# Olfato

Addon para **World of Warcraft: Forever**. Te avisa cuando estás por entrar en el rango en el que un enemigo te ve y te ataca (el "aggro"), para que puedas esquivarlo o prepararte.

Debajo de tu personaje aparecen hasta tres puntos, junto al nombre del enemigo más cercano a atacarte:

| Aviso | Qué significa |
|---|---|
| ● amarillo | te faltan entre 5 y 10 yardas para que te ataque |
| ●● naranja | te faltan menos de 5 |
| ●●● rojo, titilando | ya estás adentro: te va a atacar |

Si no hay peligro, no se ve nada. Al pasar el mouse por un enemigo, el tooltip muestra su radio (`Aggro 18 yd`).

Arriba del retrato de tu objetivo aparece a cuántas yardas está (`20-25`). El juego no les da a los addons la distancia exacta, por eso es una franja.

## Instalar

1. Bajá **[Olfato.zip](https://github.com/matud-ntc/Olfato/releases/latest/download/Olfato.zip)**. Usá ese link: el botón verde *Code → Download ZIP* y los *Source code* de la página de releases bajan una carpeta con otro nombre (`Olfato-main`, `Olfato-0.1.0`) que el juego no reconoce.
2. Abrí el zip y arrastrá la carpeta `Olfato` que hay adentro a:
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   Si usás *Extraer todo*, borrá del destino el `\Olfato` que Windows agrega al final; si no, queda `AddOns\Olfato\Olfato` y el juego no lo ve. Tiene que quedar `AddOns\Olfato\Olfato.toc`.
3. Cerrá y abrí el juego. En la selección de personaje, en **AddOns**, fijate que esté tildado.
4. Prendé las barras de nombre de enemigos (tecla **V**).

Para actualizar, repetí los mismos pasos y reemplazá la carpeta.

## Opciones

`/olf` abre una ventanita para prender y apagar cada cosa: los puntos, la línea del tooltip, el sonido (viene apagado) y la distancia al objetivo. Las mismas opciones están en **Options → AddOns → Olfato**. El botón **Probar** muestra los tres avisos y el sonido, para saber qué buscar.

En **Avisar a** escribís el alcance de un hechizo tuyo (por ejemplo `41`, el Auto Shot de un cazador con Hawk Eye). Si tenés un hechizo con ese alcance exacto, aparece su ícono al lado y Olfato le pregunta a él: la franja se parte en tu número (`40-45` pasa a `40-41` en verde si está a tiro, `41-45` en gris si no). Si no tenés ninguno, se pone verde solo cuando toda la franja entra (`30-35` con `33` queda gris, porque puede estar afuera). Vacío, no avisa.

También hay comandos:

| Comando | Qué hace |
|---|---|
| `/olf prueba` | lo mismo que el botón Probar |
| `/olf sonido` | prende o apaga el sonido cuando un enemigo pasa a rojo |
| `/olf distancia` | prende o apaga la distancia al objetivo |
| `/olf off` · `/olf on` | apaga y prende los puntos |

## Cómo calcula

- **Radio de aggro:** usa la regla de siempre de WoW clásico: 20 yardas contra un enemigo de tu mismo nivel, una menos por cada nivel que le llevás (nunca menos de 5) y una más por cada nivel que te lleva (como mucho 45).
- **Distancia:** la mide [LibRangeCheck-3.0](https://github.com/WeakAuras/LibRangeCheck-3.0) en franjas de unas 5 yardas, así que es una estimación.
- **Qué enemigos tiene en cuenta:** solo los rojos y naranjas que no están peleando. Los amarillos (neutrales) nunca atacan primero.
- **Distancia de las barras:** al entrar, sube la distancia a la que se ven las barras de nombre a 41 yardas, para que aparezcan antes de que el enemigo te vea.

No tiene en cuenta el sigilo (que achica el radio), los enemigos con un radio especial ni los grupos que vienen juntos cuando atacás a uno.

## Para desarrollo

`/olf debug` guarda lo que devuelve cada chequeo en `WTF/.../SavedVariables/Olfato.lua` (se escribe al hacer `/reload`). El cliente de Forever usa el motor 12.x: algunos datos llegan como "valores secretos" y las barras de nombre de los NPC están bloqueadas para los addons, por eso el aviso va debajo del personaje.

`lua test/simular.lua` (también con `es` o `sintemplate`) corre el addon en un WoW simulado: distancia al objetivo, ventana de opciones, panel de Settings, puntos, tooltip y barras. `lua test/cazador.lua` (o con `viejo`, para la API de hechizos anterior a 11.x) prueba **Avisar a** con los disparos de un cazador.

Para publicar una versión: subir `## Version:` en `Olfato/Olfato.toc`, después `git tag vX.Y.Z && git push --tags`. GitHub Actions arma el zip y crea la release.

## Licencia

GPL-3.0. LibRangeCheck-3.0 es MIT (ver `Olfato/Libs/LibRangeCheck-3.0/LICENSE`).
