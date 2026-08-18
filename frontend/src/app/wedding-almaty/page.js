import Link from "next/link";
import Reveal from "@/components/Reveal";
import { T } from "@/context/AppProviders";

export const metadata = {
  title: "Организация свадьбы в Алматы | MEREYTOI",
  description:
    "Организация свадьбы в Алматы под ключ: площадка, ведущий, декор, шоу-программа, артисты, фото и видео. Полная координация свадьбы от MEREYTOI.",
  alternates: {
    canonical: "https://mereytoi.kz/wedding-almaty",
  },
};

const INCLUDES = [
  {
    ru: "Подбор площадки", kz: "Алаң таңдау",
    descRu: "Банкетные залы и локации в Алматы под формат и число гостей свадьбы.",
    descKz: "Үйлену тойының форматына және қонақтар санына сай Алматыдағы банкет залдары мен алаңдар.",
  },
  {
    ru: "Ведущий", kz: "Жүргізуші",
    descRu: "Опытные свадебные ведущие на казахском и русском языках.",
    descKz: "Қазақ және орыс тілдерінде тәжірибелі үйлену тойы жүргізушілері.",
  },
  {
    ru: "Декор", kz: "Декор",
    descRu: "Оформление зала и сцены в выбранном свадебном стиле.",
    descKz: "Залды және сахнаны таңдалған үйлену тойы стилінде безендіру.",
  },
  {
    ru: "Шоу-программа", kz: "Шоу-бағдарлама",
    descRu: "Файер-шоу, лазерные и другие форматы для вечерней части свадьбы.",
    descKz: "Үйлену тойының кешкі бөлігіне арналған от-шоу, лазерлік және басқа форматтар.",
  },
  {
    ru: "Артисты", kz: "Әртістер",
    descRu: "Музыкальные коллективы, вокалисты и DJ для свадебной атмосферы.",
    descKz: "Үйлену тойы атмосферасына арналған музыкалық топтар, әншілер және DJ.",
  },
  {
    ru: "Фото и видео", kz: "Фото және видео",
    descRu: "Профессиональная съёмка свадьбы с оперативным монтажом.",
    descKz: "Үйлену тойын жедел монтажбен кәсіби түсіру.",
  },
  {
    ru: "Координация свадьбы", kz: "Үйлену тойын үйлестіру",
    descRu: "Сопровождение в день свадьбы — контролируем тайминг и все службы.",
    descKz: "Той күні қолдау көрсету — тайминг пен барлық қызметтерді бақылаймыз.",
  },
];

const STEPS = [
  { ru: "Обсуждаем формат свадьбы и бюджет", kz: "Той форматы мен бюджетті талқылаймыз" },
  { ru: "Подбираем площадку и специалистов", kz: "Алаң мен мамандарды таңдаймыз" },
  { ru: "Создаём программу и концепцию", kz: "Бағдарлама мен тұжырымдаманы құрамыз" },
  { ru: "Согласовываем детали", kz: "Бөлшектерді келісеміз" },
  { ru: "Координируем день свадьбы", kz: "Үйлену тойы күнін үйлестіреміз" },
];

const FORMATS = [
  { icon: "💍", ru: "Классическая свадьба", kz: "Классикалық үйлену тойы" },
  { icon: "✨", ru: "Современная свадьба", kz: "Заманауи үйлену тойы" },
  { icon: "🥂", ru: "Камерная свадьба", kz: "Шағын үйлену тойы" },
  { icon: "🎉", ru: "Большой свадебный банкет", kz: "Үлкен той банкеті" },
  { icon: "👨‍👩‍👧‍👦", ru: "Семейное торжество", kz: "Отбасылық мереке" },
];

const WHY_US = [
  { ru: "250+ проведённых тоев в Алматы и других городах", kz: "Алматы мен басқа қалаларда өткізілген 250+ той" },
  { ru: "15 000+ довольных гостей на наших мероприятиях", kz: "Іс-шараларымызда 15 000+ риза қонақ" },
  { ru: "8+ лет опыта в организации торжеств", kz: "Тойларды ұйымдастыруда 8+ жыл тәжірибе" },
  { ru: "Работаем в 5 городах Казахстана", kz: "Қазақстанның 5 қаласында жұмыс істейміз" },
  { ru: "Единая команда сопровождает подготовку от идеи до дня свадьбы", kz: "Идеядан той күніне дейін дайындықты бірыңғай команда сүйемелдейді" },
];

const FAQ = [
  {
    qRu: "Сколько стоит организация свадьбы в Алматы?",
    qKz: "Үйлену тойын ұйымдастыру Алматыда қанша тұрады?",
    aRu: "Стоимость зависит от выбранных услуг, площадки и числа гостей — мы подбираем состав под ваш бюджет и формируем предложение индивидуально.",
    aKz: "Құны таңдалған қызметтерге, алаңға және қонақтар санына байланысты — біз бюджетіңізге сай қызметтер жиынтығын жеке ұсынамыз.",
  },
  {
    qRu: "Можно ли заказать только отдельные услуги?",
    qKz: "Жеке қызметтерді ғана тапсырыс беруге бола ма?",
    aRu: "Да, можно выбрать как полную организацию свадьбы, так и отдельные услуги — например, только ведущего или декор.",
    aKz: "Иә, той ұйымдастыруды толық та, жеке қызметтерді де (мысалы, тек жүргізуші немесе декор) таңдауға болады.",
  },
  {
    qRu: "Помогаете ли вы подобрать свадебную площадку?",
    qKz: "Үйлену тойына арналған алаң таңдауға көмектесесіздер ме?",
    aRu: "Да, помогаем подобрать банкетный зал или локацию, подходящую по вместимости и формату свадьбы.",
    aKz: "Иә, той форматы мен қонақтар санына сай банкет залын немесе алаңды таңдауға көмектесеміз.",
  },
  {
    qRu: "Можно ли заказать отдельно ведущего, декор или шоу-программу?",
    qKz: "Жүргізуші, декор немесе шоу-бағдарламаны бөлек тапсырыс беруге бола ма?",
    aRu: "Да, эти услуги можно заказать по отдельности через каталог услуг или в рамках полной организации свадьбы.",
    aKz: "Иә, бұл қызметтерді қызметтер каталогы арқылы бөлек немесе той ұйымдастырудың құрамында тапсырыс беруге болады.",
  },
  {
    qRu: "С чего начать подготовку свадьбы?",
    qKz: "Дайындықты неден бастау керек?",
    aRu: "Оставьте заявку — мы свяжемся с вами, обсудим формат и бюджет и предложим варианты организации.",
    aKz: "Өтінім қалдырыңыз — сізбен байланысып, форматы мен бюджетті талқылаймыз және ұйымдастыру нұсқаларын ұсынамыз.",
  },
];

export default function WeddingAlmatyPage() {
  return (
    <>
      <section className="page-hero" style={{ paddingBottom: 70 }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <p className="breadcrumb">
            <Link href="/"><T ru="Главная" kz="Басты бет" /></Link>
            <span>/</span>
            <span className="is-current"><T ru="Организация свадьбы в Алматы" kz="Алматыда үйлену тойын ұйымдастыру" /></span>
          </p>
          <h1><T ru="Организация свадьбы в Алматы" kz="Алматыда үйлену тойын ұйымдастыру" /></h1>
          <p>
            <T
              ru="Помогаем подготовить свадьбу от идеи до дня проведения: площадка, ведущий, декор, шоу-программа, артисты, фото и видео."
              kz="Үйлену тойын идеядан бастап өткізу күніне дейін дайындауға көмектесеміз: алаң, жүргізуші, декор, шоу-бағдарлама, әртістер, фото және видео."
            />
          </p>
          <div className="services__cta" style={{ marginTop: 30 }}>
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать свадьбу" kz="Той тапсырыс беру" />
            </Link>
          </div>
        </div>
      </section>

      {/* Section A — Свадьба под ключ */}
      <section className="toi-section">
        <div className="container toi-section__intro">
          <Reveal as="p" className="section-eyebrow"><T ru="ПОД КЛЮЧ" kz="ТОЛЫҚ ҚЫЗМЕТ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Свадьба под ключ" kz="Үйлену тойын толық ұйымдастыру" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="MEREYTOI берёт на себя координацию свадьбы в Алматы — от первой идеи до дня торжества. Помогаем определить концепцию, подобрать площадку, ведущего и артистов, продумать программу и декор, организовать фото- и видеосъёмку и держим под контролем каждую деталь подготовки в день свадьбы."
              kz="MEREYTOI Алматыдағы үйлену тойын үйлестіруге алады — алғашқы идеядан той күніне дейін. Тұжырымдаманы анықтауға, алаң, жүргізуші және әртістерді таңдауға, бағдарлама мен декорды ойластыруға, фото және видео түсірілімді ұйымдастыруға көмектесеміз және той күні дайындықтың әр бөлшегін бақылауда ұстаймыз."
            />
          </Reveal>
        </div>
      </section>

      {/* Section B — Что входит в организацию свадьбы */}
      <section className="toi-section toi-section--alt">
        <div className="container">
          <Reveal as="p" className="section-eyebrow"><T ru="СОСТАВ УСЛУГ" kz="ҚЫЗМЕТТЕР ҚҰРАМЫ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Что входит в организацию свадьбы" kz="Той ұйымдастыруға не кіреді" /></Reveal>

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
          <Reveal as="h2" className="section-title"><T ru="Планируете свадьбу в Алматы?" kz="Алматыда үйлену тойын жоспарлап жатырсыз ба?" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="Подберём площадку, ведущего, декор и программу под формат вашего праздника."
              kz="Мерекеңіздің форматына сай алаң, жүргізуші, декор және бағдарлама таңдаймыз."
            />
          </Reveal>
          <div className="services__cta">
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать свадьбу" kz="Той тапсырыс беру" />
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
