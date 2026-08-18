// tw-bridge — el puente entre el markup Tailwind ya escrito del viz y los
// tokens del design system.
//
// El viz tiene ~700 usos de clases de color Tailwind y los usa
// semánticamente sin excepción: slate = neutral, indigo/blue/sky/violet =
// marca, red/rose = negativo, emerald = positivo, amber = precaución,
// pink = acento. En vez de reescribir esos 700 sitios, aquí se REDEFINE la
// paleta de Tailwind apuntándola a las rampas de tokens.css.
//
// Consecuencias, todas gratis:
//   · el viz entero se repinta con el tema del cliente (tema.json),
//   · y gana tema oscuro, porque las rampas invierten sus polos bajo
//     [data-theme="dark"] — `bg-slate-100` es superficie clara en claro y
//     oscura en oscuro sin una sola clase condicional.
//
// Este archivo se carga DESPUÉS del CDN de Tailwind y antes del primer
// pintado; Play CDN observa `tailwind.config` y (re)genera el CSS.
//
// Al portar un componente a las clases del DS (.btn, .card, .kpi…) sus
// utilidades de color desaparecen y dejan de pasar por aquí. El puente es
// el piso, no el techo.

(function () {
  // Un color de la config que respeta el modificador de opacidad de Tailwind
  // (`bg-white/50`, `even:bg-slate-50/60`). Sin esto, v3 no sabe aplicarle
  // alfa a un var() y descarta la clase.
  //
  // OJO con la guarda: para una clase SIN modificador, v3 no pasa `undefined`
  // sino la cadena `var(--tw-bg-opacity, 1)` — su mecanismo normal de alfa, que
  // no sirve con un var() de color. Solo un número entre 0 y 1 es un
  // modificador de verdad; cualquier otra cosa devuelve el color pelado.
  const t = (name) => ({ opacityValue }) => {
    const a = Number(opacityValue);
    return Number.isFinite(a) && a >= 0 && a <= 1
      ? `color-mix(in srgb, var(${name}) ${a * 100}%, transparent)`
      : `var(${name})`;
  };

  const STEPS = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900];
  const ramp = (prefix) => Object.fromEntries(STEPS.map((s) => [s, t(`--${prefix}-${s}`)]));

  const neutral = ramp("n"); // slate
  const brand = ramp("b"); // indigo · blue · sky · violet
  const positive = ramp("pos"); // emerald
  const negative = ramp("neg"); // red · rose
  const caution = ramp("cau"); // amber
  const accent = ramp("acc"); // pink

  tailwind.config = {
    theme: {
      extend: {
        colors: {
          slate: neutral,
          gray: neutral,
          zinc: neutral,
          neutral: neutral,
          stone: neutral,
          indigo: brand,
          blue: brand,
          sky: brand,
          violet: brand,
          purple: brand,
          emerald: positive,
          green: positive,
          teal: positive,
          red: negative,
          rose: negative,
          amber: caution,
          yellow: caution,
          orange: caution,
          pink: accent,
          fuchsia: accent,
        },

        // `white` es el único nombre que significa dos cosas distintas según
        // la utilidad: como fondo es la superficie de la card (y en oscuro
        // deja de ser blanco), pero como texto es la tinta sobre un sólido de
        // marca, que sigue siendo clara en ambos temas. Tailwind permite
        // separarlas porque backgroundColor y textColor son escalas propias.
        backgroundColor: { white: t("--surface-2") },
        borderColor: { white: t("--surface-2") },
        textColor: { white: t("--brand-on-solid") },

        fontFamily: {
          sans: ["var(--font-ui)"],
          mono: ["var(--font-mono)"],
        },
        borderRadius: {
          DEFAULT: "var(--r-sm)",
          md: "var(--r-md)",
          lg: "var(--r-lg)",
          xl: "var(--r-xl)",
          "2xl": "var(--r-2xl)",
        },
        boxShadow: {
          sm: "var(--sh-1)",
          DEFAULT: "var(--sh-2)",
          md: "var(--sh-2)",
          lg: "var(--sh-3)",
          xl: "var(--sh-4)",
        },
      },
    },
  };
})();
