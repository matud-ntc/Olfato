# Olfato

Addon para **World of Warcraft: Forever**. Te avisa cuando estás por entrar en el rango en el que un enemigo te ve y te ataca (el "aggro"), para que puedas esquivarlo o prepararte.

Debajo de tu personaje aparecen hasta tres puntos, junto al nombre del enemigo más cercano a atacarte:

| Aviso | Qué significa |
|---|---|
| ● amarillo | te faltan entre 5 y 10 yardas para que te ataque |
| ●● naranja | te faltan menos de 5 |
| ●●● rojo, titilando | ya estás adentro: te va a atacar |

Si no hay peligro, no se ve nada. Al pasar el mouse por un enemigo, el tooltip muestra su radio (`Aggro 18 yd`).

## Instalar

1. Bajá **[Olfato.zip](https://github.com/matud-ntc/Olfato/releases/latest/download/Olfato.zip)**.
2. Descomprimilo dentro de la carpeta de addons de Forever:
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   Tiene que quedar la carpeta `Olfato` adentro de `AddOns`.
3. Cerrá y abrí el juego. En la selección de personaje, en **AddOns**, fijate que esté tildado.
4. Prendé las barras de nombre de enemigos (tecla **V**).

Para actualizar, repetí los mismos pasos y reemplazá la carpeta.

## Comandos

| Comando | Qué hace |
|---|---|
| `/olf prueba` | muestra los tres avisos y el sonido, para saber qué buscar |
| `/olf sonido` | suena un aviso cuando un enemigo pasa a rojo (viene apagado) |
| `/olf off` · `/olf on` | lo apaga y lo prende |

## Cómo calcula

- **Radio de aggro:** usa la regla de siempre de WoW clásico: 20 yardas contra un enemigo de tu mismo nivel, una menos por cada nivel que le llevás (nunca menos de 5) y una más por cada nivel que te lleva (como mucho 45).
- **Distancia:** la mide [LibRangeCheck-3.0](https://github.com/WeakAuras/LibRangeCheck-3.0) en franjas de unas 5 yardas, así que es una estimación.
- **Qué enemigos tiene en cuenta:** solo los rojos y naranjas que no están peleando. Los amarillos (neutrales) nunca atacan primero.
- **Distancia de las barras:** al entrar, sube la distancia a la que se ven las barras de nombre a 41 yardas, para que aparezcan antes de que el enemigo te vea.

No tiene en cuenta el sigilo (que achica el radio), los enemigos con un radio especial ni los grupos que vienen juntos cuando atacás a uno.

## Para desarrollo

`/olf debug` guarda lo que devuelve cada chequeo en `WTF/.../SavedVariables/Olfato.lua` (se escribe al hacer `/reload`). El cliente de Forever usa el motor 12.x: algunos datos llegan como "valores secretos" y las barras de nombre de los NPC están bloqueadas para los addons, por eso el aviso va debajo del personaje.

Para publicar una versión: subir `## Version:` en `Olfato/Olfato.toc`, después `git tag vX.Y.Z && git push --tags`. GitHub Actions arma el zip y crea la release.

## Licencia

GPL-3.0. LibRangeCheck-3.0 es MIT (ver `Olfato/Libs/LibRangeCheck-3.0/LICENSE`).
