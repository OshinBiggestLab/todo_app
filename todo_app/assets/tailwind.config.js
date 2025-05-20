// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/todo_app_web.ex",
    "../lib/todo_app_web/**/*.*ex",
  ],
  theme: {
    extend: {
      screens: {
        sm: "375px",
        md: "720px",
        lg: "1080px",
        xl: "1440px",
      },
      colors: {
        //  1 = light
        // 11 = very light
        // 0 = dark
        // 00 = very dark
        // gb = grayish_blue

        // Primary
        brightBlue: "hsl(220, 98%, 61%)",
        linearGradient: "hsl(192, 100%, 67%)",
        babyPurple: "hsl(280, 87%, 65%)",
        // Light Theme
        grey_11: "hsl(0, 0%, 98%)",
        gb_11: "hsl(236, 33%, 92%)",
        gb_1: "hsl(233, 11%, 84%)",
        gb_0: "hsl(236, 9%, 61%)",
        gb_001: "hsl(235, 19%, 35%)",
        // Dark Theme
        blue_00: "hsl(235, 21%, 11%)",
        desaturated_blue00: "hsl(235, 24%, 19%)",
        light_grayish_blue: "hsl(234, 39%, 85%)",
        gb_1h: "hsl(236, 33%, 92%)", //(hover)
        gb_02: "hsl(234, 11%, 52%)",
        gb_002: "hsl(233, 14%, 35%)",
        gb_003: "hsl(237, 14%, 26%)",
      },
      fontFamily: {
        josefinSans: ["Josefin Sans"],
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ])
    ),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized");
      let values = {};
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
          let name = path.basename(file, ".svg") + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, "");
            let size = theme("spacing.6");
            if (name.endsWith("-mini")) {
              size = theme("spacing.5");
            } else if (name.endsWith("-micro")) {
              size = theme("spacing.4");
            }
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: size,
              height: size,
            };
          },
        },
        { values }
      );
    }),
  ],
};
