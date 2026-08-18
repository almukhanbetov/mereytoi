import Link from "next/link";
import Reveal from "@/components/Reveal";
import { T } from "@/context/AppProviders";

export const metadata = {
  title: "Организация юбилея в Алматы | MEREYTOI",
  description:
    "Организация юбилея в Алматы под ключ: площадка, ведущий, декор, шоу-программа, артисты, фото и видео. Полная координация юбилея от MEREYTOI.",
  alternates: {
    canonical: "https://mereytoi.kz/yubiley-almaty",
  },
};

const INCLUDES = [
  {
    ru: "Подбор площадки", kz: "Алаң таңдау",
    descRu: "Банкетные залы и локации в Алматы под формат и число гостей юбилея.",
    descKz: "Мерейтойдың форматына және қонақтар санына сай Алматыдағы банкет залдары мен алаңдар.",
  },
  {
    ru: "Ведущий", kz: "Жүргізуші",
    descRu: "Опытные ведущие для юбилея на казахском и русском языках.",
    descKz: "Мерейтойға арналған тәжірибелі жүргізушілер, қазақ және орыс тілдерінде.",
  },
  {
    ru: "Декор", kz: "Декор",
    descRu: "Оформление зала и сцены в выбранном стиле — от классики до современных решений.",
    descKz: "Залды және сахнаны таңдалған стильде безендіру — классикадан заманауи шешімдерге дейін.",
  },
  {
    ru: "Шоу-программа", kz: "Шоу-бағдарлама",
    descRu: "Файер-шоу, лазерные и другие форматы для вечерней части юбилея.",
    descKz: "Мерейтойдың кешкі бөлігіне арналған от-шоу, лазерлік және басқа форматтар.",
  },
  {
    ru: "Артисты", kz: "Әртістер",
    descRu: "Музыкальные коллективы, вокалисты и DJ для атмосферы праздника.",
    descKz: "Мерекенің атмосферасына арналған музыкалық топтар, әншілер және DJ.",
  },
  {
    ru: "Фото и видео", kz: "Фото және видео",
    descRu: "Профессиональная съёмка мероприятия с оперативным монтажом.",
    descKz: "Іс-шараны жедел монтажбен кәсіби түсіру.",
  },
  {
    ru: "Координация мероприятия", kz: "Іс-шараны үйлестіру",
    descRu: "Сопровождение в день юбилея — контролируем тайминг и все службы.",
    descKz: "Мерейтой күні қолдау көрсету — тайминг пен барлық қызметтерді бақылаймыз.",
  },
];

const STEPS = [
  { ru: "Обсуждаем формат юбилея и бюджет", kz: "Мерейтой форматы мен бюджетті талқылаймыз" },
  { ru: "Подбираем площадку и специалистов", kz: "Алаң мен мамандарды таңдаймыз" },
  { ru: "Формируем программу мероприятия", kz: "Іс-шара бағдарламасын құрамыз" },
  { ru: "Согласовываем детали", kz: "Бөлшектерді келісеміз" },
  { ru: "Координируем день проведения", kz: "Өткізу күнін үйлестіреміз" },
];

const FORMATS = [
  { icon: "🎂", ru: "Юбилей 30 лет", kz: "30 жылдық мерейтой" },
  { icon: "🎉", ru: "Юбилей 40 лет", kz: "40 жылдық мерейтой" },
  { icon: "✨", ru: "Юбилей 50 лет", kz: "50 жылдық мерейтой" },
  { icon: "🥂", ru: "Юбилей 60 лет", kz: "60 жылдық мерейтой" },
  { icon: "👨‍👩‍👧‍👦", ru: "Семейный юбилей", kz: "Отбасылық мерейтой" },
  { icon: "🍽️", ru: "Большой банкет", kz: "Үлкен банкет" },
];

const WHY_US = [
  { ru: "250+ проведённых тоев в Алматы и других городах", kz: "Алматы мен басқа қалаларда өткізілген 250+ той" },
  { ru: "15 000+ довольных гостей на наших мероприятиях", kz: "Іс-шараларымызда 15 000+ риза қонақ" },
  { ru: "8+ лет опыта в организации торжеств", kz: "Тойларды ұйымдастыруда 8+ жыл тәжірибе" },
  { ru: "Работаем в 5 городах Казахстана", kz: "Қазақстанның 5 қаласында жұмыс істейміз" },
  { ru: "Единая команда сопровождает подготовку от идеи до дня мероприятия", kz: "Идеядан той күніне дейін дайындықты бірыңғай команда сүйемелдейді" },
];

const FAQ = [
  {
    qRu: "Сколько стоит организация юбилея в Алматы?",
    qKz: "Мерейтой ұйымдастыру Алматыда қанша тұрады?",
    aRu: "Стоимость зависит от выбранных услуг, площадки и числа гостей — мы подбираем состав под ваш бюджет и формируем предложение индивидуально.",
    aKz: "Құны таңдалған қызметтерге, алаңға және қонақтар санына байланысты — біз бюджетіңізге сай қызметтер жиынтығын жеке ұсынамыз.",
  },
  {
    qRu: "Можно ли заказать только отдельные услуги?",
    qKz: "Жеке қызметтерді ғана тапсырыс беруге бола ма?",
    aRu: "Да, можно выбрать как полную организацию юбилея, так и отдельные услуги — например, только ведущего или декор.",
    aKz: "Иә, мерейтойды толық ұйымдастыруды да, жеке қызметтерді де (мысалы, тек жүргізуші немесе декор) таңдауға болады.",
  },
  {
    qRu: "Помогаете ли вы подобрать площадку?",
    qKz: "Алаң таңдауға көмектесесіздер ме?",
    aRu: "Да, помогаем подобрать банкетный зал или локацию, подходящую по вместимости и формату юбилея.",
    aKz: "Иә, мерейтой форматы мен қонақтар санына сай банкет залын немесе алаңды таңдауға көмектесеміз.",
  },
  {
    qRu: "Можно ли отдельно заказать ведущего, артистов или шоу-программу?",
    qKz: "Жүргізушіні, әртістерді немесе шоу-бағдарламаны бөлек тапсырыс беруге бола ма?",
    aRu: "Да, эти услуги можно заказать по отдельности через каталог услуг или в рамках полной организации юбилея.",
    aKz: "Иә, бұл қызметтерді қызметтер каталогы арқылы бөлек немесе мерейтойды ұйымдастырудың құрамында тапсырыс беруге болады.",
  },
  {
    qRu: "С чего начать подготовку юбилея?",
    qKz: "Дайындықты неден бастау керек?",
    aRu: "Оставьте заявку — мы свяжемся с вами, обсудим формат и бюджет и предложим варианты организации.",
    aKz: "Өтінім қалдырыңыз — сізбен байланысып, форматы мен бюджетті талқылаймыз және ұйымдастыру нұсқаларын ұсынамыз.",
  },
];

export default function YubileyAlmatyPage() {
  return (
    <>
      <section className="page-hero" style={{ paddingBottom: 70 }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <p className="breadcrumb">
            <Link href="/"><T ru="Главная" kz="Басты бет" /></Link>
            <span>/</span>
            <span className="is-current"><T ru="Организация юбилея в Алматы" kz="Алматыда мерейтой ұйымдастыру" /></span>
          </p>
          <h1><T ru="Организация юбилея в Алматы" kz="Алматыда мерейтой ұйымдастыру" /></h1>
          <p>
            <T
              ru="Помогаем подготовить юбилей от идеи до дня проведения: площадка, ведущий, декор, шоу-программа, артисты, фото и видео."
              kz="Мерейтойды идеядан бастап өткізу күніне дейін дайындауға көмектесеміз: алаң, жүргізуші, декор, шоу-бағдарлама, әртістер, фото және видео."
            />
          </p>
          <div className="services__cta" style={{ marginTop: 30 }}>
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать юбилей" kz="Мерейтой тапсырыс беру" />
            </Link>
          </div>
        </div>
      </section>

      {/* Section A — Юбилей под ключ */}
      <section className="toi-section">
        <div className="container toi-section__intro">
          <Reveal as="p" className="section-eyebrow"><T ru="ПОД КЛЮЧ" kz="ТОЛЫҚ ҚЫЗМЕТ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Юбилей под ключ" kz="Мерейтойды толық ұйымдастыру" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="MEREYTOI берёт на себя координацию юбилея в Алматы — от первой идеи до дня торжества. Помогаем определить концепцию праздника, подобрать площадку, ведущего и артистов, продумать программу и декор, организовать фото- и видеосъёмку и держим под контролем каждую деталь подготовки в день мероприятия."
              kz="MEREYTOI Алматыдағы мерейтойды үйлестіруге алады — алғашқы идеядан той күніне дейін. Мерекенің тұжырымдамасын анықтауға, алаң, жүргізуші және әртістерді таңдауға, бағдарлама мен декорды ойластыруға, фото және видео түсірілімді ұйымдастыруға көмектесеміз және іс-шара күні дайындықтың әр бөлшегін бақылауда ұстаймыз."
            />
          </Reveal>
        </div>
      </section>

      {/* Section B — Что входит в организацию юбилея */}
      <section className="toi-section toi-section--alt">
        <div className="container">
          <Reveal as="p" className="section-eyebrow"><T ru="СОСТАВ УСЛУГ" kz="ҚЫЗМЕТТЕР ҚҰРАМЫ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Что входит в организацию юбилея" kz="Мерейтойды ұйымдастыруға не кіреді" /></Reveal>

          <div className="services__grid">
            {INCLUDES.map((item, i) => (
              <Reveal as="article" className="card" key={item.ru} delay={(i % 4) * 70}>
                <h3><T ru={item.ru} kz={item.kz} /></h3>
                <p><T ru={item.descRu} kz={item.descKz} /></p>
              </Reveal>
            ))}
          </div>

          <Reveal className="services__cta">
            <Link href="/services" className="btn btn--outline">
              <T ru="Посмотреть все услуги" kz="Барлық қызметтерді қарау" />
            </Link>
          </Reveal>
        </div>
      </section>

      {/* Section C — Как проходит подготовка */}
      <section className="toi-section">
        <div className="container">
          <Reveal as="p" className="section-eyebrow"><T ru="ПРОЦЕСС" kz="ҮДЕРІС" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Как проходит подготовка" kz="Дайындық қалай өтеді" /></Reveal>

          <div className="services__grid toi-steps">
            {STEPS.map((step, i) => (
              <Reveal as="article" className="card" key={step.ru} delay={(i % 4) * 70}>
                <div className="card__icon">{String(i + 1).padStart(2, "0")}</div>
                <h3><T ru={step.ru} kz={step.kz} /></h3>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* Section D — Для каких форматов */}
      <section className="toi-section toi-section--alt">
        <div className="container toi-section__intro">
          <Reveal as="p" className="section-eyebrow"><T ru="ФОРМАТЫ" kz="ФОРМАТТАР" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Для каких форматов" kz="Қандай форматтарға" /></Reveal>
          <Reveal as="ul" className="contacts__list" style={{ marginTop: 34, textAlign: 'left', display: 'inline-flex', flexDirection: 'column' }}>
            {FORMATS.map((f) => (
              <li key={f.ru}>
                <span className="contacts__icon">{f.icon}</span>
                <span><T ru={f.ru} kz={f.kz} /></span>
              </li>
            ))}
          </Reveal>
        </div>
      </section>

      {/* Section E — Почему MEREYTOI */}
      <section className="toi-section">
        <div className="container toi-section__intro">
          <Reveal as="p" className="section-eyebrow"><T ru="ПОЧЕМУ МЫ" kz="НЕГЕ БІЗ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Почему MEREYTOI" kz="Неге MEREYTOI" /></Reveal>
          <Reveal as="ul" className="contacts__list" style={{ marginTop: 34, textAlign: 'left', display: 'inline-flex', flexDirection: 'column' }}>
            {WHY_US.map((w) => (
              <li key={w.ru}>
                <span className="contacts__icon">✓</span>
                <span><T ru={w.ru} kz={w.kz} /></span>
              </li>
            ))}
          </Reveal>
        </div>
      </section>

      {/* Section F — CTA */}
      <section className="toi-section toi-section--alt">
        <div className="container toi-section__intro">
          <Reveal as="h2" className="section-title"><T ru="Планируете юбилей в Алматы?" kz="Алматыда мерейтой жоспарлап жатырсыз ба?" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="Подберём площадку, ведущего, декор и программу под формат вашего праздника."
              kz="Мерекеңіздің форматына сай алаң, жүргізуші, декор және бағдарлама таңдаймыз."
            />
          </Reveal>
          <div className="services__cta">
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать юбилей" kz="Мерейтой тапсырыс беру" />
            </Link>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="toi-section">
        <div className="container">
          <Reveal as="p" className="section-eyebrow"><T ru="ВОПРОСЫ" kz="СҰРАҚТАР" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Частые вопросы" kz="Жиі қойылатын сұрақтар" /></Reveal>

          <div className="toi-faq">
            {FAQ.map((item) => (
              <details key={item.qRu}>
                <summary><T ru={item.qRu} kz={item.qKz} /></summary>
                <p><T ru={item.aRu} kz={item.aKz} /></p>
              </details>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
