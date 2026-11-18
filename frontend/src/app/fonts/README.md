# Шрифты сайта

Шрифты хранятся в проекте и подключаются через `next/font/local`
(`src/app/layout.js`), поэтому сборка не обращается к Google Fonts.

| Файл | Гарнитура | Оси | Лицензия |
|---|---|---|---|
| `Montserrat-wght.woff2` | Montserrat 9.000 | wght 100–900 | `Montserrat-OFL.txt` (SIL OFL 1.1) |
| `PlayfairMEREYTOIWeb-wght.woff2` | Playfair Display 1.203 | wght 400–900 | `PlayfairDisplay-OFL.txt` (SIL OFL 1.1) |

Исходники — variable TTF из https://github.com/google/fonts
(`ofl/montserrat` @ 26975696d3c3, `ofl/playfairdisplay` @ f4f3b47f2c7e).
Версии те же, что сейчас отдаёт Google Fonts.

Файлы урезаны (`pyftsubset --layout-features='*' --flavor=woff2`) до тех же
наборов символов, что Google Fonts отдаёт для этих гарнитур:

- Montserrat — latin, latin-ext, cyrillic, cyrillic-ext, vietnamese;
- Playfair Display — latin, latin-ext, cyrillic, vietnamese.
  Казахских букв Ә Ғ Қ Ң Ө Ү Һ в веб-версии Google нет, поэтому их нет и
  здесь: внешний вид совпадает с прежним.

«Playfair Display» — зарезервированное имя (Reserved Font Name) по OFL, а
урезанный файл считается изменённой версией. Поэтому внутреннее имя файла
изменено на «Playfair MEREYTOI Web». Контуры глифов не менялись.
