# Olfato

Addon para **World of Warcraft: Forever**. Sobre la barra de nombre de cada bicho hostil aparecen puntitos a medida que te acercás a su rango de aggro:

| | Distancia al borde del aggro |
|---|---|
| ● amarillo | 5–10 yd |
| ●● naranja | menos de 5 yd |
| ●●● rojo titilando | adentro: te va a atacar |

El tooltip del bicho muestra su radio (`Aggro 18 yd`).

- Radio estimado con la regla de vanilla: 20 yd a igual nivel, 1 yd menos por cada nivel que le llevás (mínimo 5) y 1 más por cada nivel que te lleva (hasta +25).
- Distancia con [LibRangeCheck-3.0](https://github.com/WeakAuras/LibRangeCheck-3.0) (MIT), en franjas de ~5 yd.
- Solo bichos rojos/naranjas fuera de combate; los amarillos (neutrales) no inician peleas.
- Necesita las placas de nombre de enemigos (V). Al entrar sube `nameplateMaxDistance` a 41 si estaba más bajo, para que las placas aparezcan antes que el aggro.

`/olf` estado y distancia al target · `/olf sonido` aviso sonoro al entrar en rojo · `/olf off` / `/olf on`.

No contempla sigilo, radios custom de algunos bichos ni linkeo de grupos (pullear uno trae a sus amigos).

## Licencia

GPL-3.0. LibRangeCheck-3.0 es MIT (ver `Olfato/Libs/LibRangeCheck-3.0/LICENSE`).
