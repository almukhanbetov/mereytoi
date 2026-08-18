import Link from "next/link";
import Reveal from "@/components/Reveal";
import { T } from "@/context/AppProviders";

export const metadata = {
  title: "Организация корпоратива в Алматы | MEREYTOI",
  description:
    "Организация корпоратива в Алматы под ключ: площадка, ведущий, шоу-программа, артисты, декор, фото и видео. Полная координация корпоративного мероприятия от MEREYTOI.",
  alternates: {
    canonical: "https://mereytoi.kz/corporate-almaty",
  },
};

const INCLUDES = [
  {
    ru: "Подбор площадки", kz: "Алаң таңдау",
    descRu: "Залы и локации в Алматы под формат и число участников корпоратива.",
    descKz: "Корпоративтің форматына және қатысушылар санына сай Алматыдағы залдар мен алаңдар.",
  },
  {
    ru: "Ведущий", kz: "Жүргізуші",
    descRu: "Ведущие для корпоративного вечера на казахском и русском языках.",
    descKz: "Қазақ және орыс тілдерінде корпоративтік кешке арналған жүргізушілер.",
  },
  {
    ru: "Шоу-программа", kz: "Шоу-бағдарлама",
    descRu: "Развлекательные форматы для деловой и праздничной части мероприятия.",
    descKz: "Іс-шараның іскерлік және мерекелік бөлігіне арналған ойын-сауық форматтары.",
  },
  {
    ru: "Артисты", kz: "Әртістер",
    descRu: "Музыкальные коллективы, вокалисты и DJ для корпоративного мероприятия.",
    descKz: "Корпоративтік іс-шараға арналған музыкалық топтар, әншілер және DJ.",
  },
  {
    ru: "Декор", kz: "Декор",
    descRu: "Оформление зала и сцены в стиле, соответствующем формату компании.",
    descKz: "Компания форматына сай залды және сахнаны безендіру.",
  },
  {
    ru: "Фото и видео", kz: "Фото және видео",
    descRu: "Профессиональная съёмка мероприятия с оперативным монтажом.",
    descKz: "Іс-шараны жедел монтажбен кәсіби түсіру.",
  },
  {
    ru: "Координация мероприятия", kz: "Іс-шараны үйлестіру",
    descRu: "Сопровождение в день корпоратива — контролируем тайминг и все службы.",
    descKz: "Іс-шара күні қолдау көрсету — тайминг пен барлық қызметтерді бақылаймыз.",
  },
];

const STEPS = [
  { ru: "Обсуждаем формат и бюджет", kz: "Форматы мен бюджетті талқылаймыз" },
  { ru: "Подбираем площадку и специалистов", kz: "Алаң мен мамандарды таңдаймыз" },
  { ru: "Формируем программу мероприятия", kz: "Іс-шара бағдарламасын құрамыз" },
  { ru: "Согласовываем детали", kz: "Бөлшектерді келісеміз" },
  { ru: "Координируем день проведения", kz: "Өткізу күнін үйлестіреміз" },
];

const FORMATS = [
  { icon: "🎄", ru: "Новогодний корпоратив", kz: "Жаңа жылдық корпоратив" },
  { icon: "🤝", ru: "Тимбилдинг", kz: "Тимбилдинг" },
  { icon: "🥂", ru: "Корпоративный вечер", kz: "Корпоративтік кеш" },
  { icon: "🏢", ru: "Юбилей компании", kz: "Компания мерейтойы" },
  { icon: "💼", ru: "Деловое мероприятие", kz: "Іскерлік іс-шара" },
  { icon: "🎉", ru: "Праздничное мероприятие для сотрудников", kz: "Қызметкерлерге арналған мерекелік іс-шара" },
];

const WHY_US = [
  { ru: "250+ проведённых мероприятий в Алматы и других городах", kz: "Алматы мен басқа қалаларда өткізілген 250+ іс-шара" },
  { ru: "15 000+ довольных гостей на наших мероприятиях", kz: "Іс-шараларымызда 15 000+ риза қонақ" },
  { ru: "8+ лет опыта в организации торжеств", kz: "Мерекелерді ұйымдастыруда 8+ жыл тәжірибе" },
  { ru: "Работаем в 5 городах Казахстана", kz: "Қазақстанның 5 қаласында жұмыс істейміз" },
  { ru: "Единая команда сопровождает подготовку от идеи до дня мероприятия", kz: "Идеядан іс-шара күніне дейін дайындықты бірыңғай команда сүйемелдейді" },
];

const FAQ = [
  {
    qRu: "Сколько стоит организация корпоратива в Алматы?",
    qKz: "Корпоративті ұйымдастыру Алматыда қанша тұрады?",
    aRu: "Стоимость зависит от выбранных услуг, площадки и числа участников — мы подбираем состав под ваш бюджет и формируем предложение индивидуально.",
    aKz: "Құны таңдалған қызметтерге, алаңға және қатысушылар санына байланысты — біз бюджетіңізге сай қызметтер жиынтығын жеке ұсынамыз.",
  },
  {
    qRu: "Можно ли заказать только отдельные услуги?",
    qKz: "Жеке қызметтерді ғана тапсырыс беруге бола ма?",
    aRu: "Да, можно выбрать как полную организацию корпоратива, так и отдельные услуги — например, только ведущего или шоу-программу.",
    aKz: "Иә, корпоративті толық ұйымдастыруды да, жеке қызметтерді де (мысалы, тек жүргізуші немесе шоу-бағдарлама) таңдауға болады.",
  },
  {
    qRu: "Помогаете ли вы подобрать площадку для корпоратива?",
    qKz: "Корпоративке арналған алаң таңдауға көмектесесіздер ме?",
    aRu: "Да, помогаем подобрать зал или локацию, подходящую по вместимости и формату мероприятия.",
    aKz: "Иә, іс-шараның форматы мен қатысушылар санына сай залды немесе алаңды таңдауға көмектесеміз.",
  },
  {
    qRu: "Можно ли отдельно заказать ведущего или шоу-программу?",
    qKz: "Жүргізушіні немесе шоу-бағдарламаны бөлек тапсырыс беруге бола ма?",
    aRu: "Да, эти услуги можно заказать по отдельности через каталог услуг или в рамках полной организации корпоратива.",
    aKz: "Иә, бұл қызметтерді қызметтер каталогы арқылы бөлек немесе корпоративті ұйымдастырудың құрамында тапсырыс беруге болады.",
  },
  {
    qRu: "С чего начать подготовку корпоративного мероприятия?",
    qKz: "Дайындықты неден бастау керек?",
    aRu: "Оставьте заявку — мы свяжемся с вами, обсудим формат и бюджет и предложим варианты организации.",
    aKz: "Өтінім қалдырыңыз — сізбен байланысып, форматы мен бюджетті талқылаймыз және ұйымдастыру нұсқаларын ұсынамыз.",
  },
];

export default function CorporateAlmatyPage() {
  return (
    <>
      <section className="page-hero" style={{ paddingBottom: 70 }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <p className="breadcrumb">
            <Link href="/"><T ru="Главная" kz="Басты бет" /></Link>
            <span>/</span>
            <span className="is-current"><T ru="Организация корпоратива в Алматы" kz="Алматыда корпоратив ұйымдастыру" /></span>
          </p>
          <h1><T ru="Организация корпоратива в Алматы" kz="Алматыда корпоратив ұйымдастыру" /></h1>
          <p>
            <T
              ru="Помогаем подготовить корпоративное мероприятие от идеи до дня проведения: площадка, ведущий, шоу-программа, артисты, декор, фото и видео."
              kz="Корпоративтік іс-шараны идеядан бастап өткізу күніне дейін дайындауға көмектесеміз: алаң, жүргізуші, шоу-бағдарлама, әртістер, декор, фото және видео."
            />
          </p>
          <div className="services__cta" style={{ marginTop: 30 }}>
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать корпоратив" kz="Корпоратив тапсырыс беру" />
            </Link>
          </div>
        </div>
      </section>

      {/* Section A — Корпоратив под ключ */}
      <section className="toi-section">
        <div className="container toi-section__intro">
          <Reveal as="p" className="section-eyebrow"><T ru="ПОД КЛЮЧ" kz="ТОЛЫҚ ҚЫЗМЕТ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Корпоратив под ключ" kz="Корпоративті толық ұйымдастыру" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="MEREYTOI берёт на себя координацию корпоративного мероприятия в Алматы — от первой идеи до дня проведения. Помогаем определить концепцию, подобрать площадку, ведущего и артистов, продумать развлекательную программу и декор, организовать фото- и видеосъёмку и держим под контролем каждую деталь подготовки в день мероприятия."
              kz="MEREYTOI Алматыдағы корпоративтік іс-шараны үйлестіруге алады — алғашқы идеядан өткізу күніне дейін. Тұжырымдаманы анықтауға, алаң, жүргізуші және әртістерді таңдауға, ойын-сауық бағдарламасы мен декорды ойластыруға, фото және видео түсірілімді ұйымдастыруға көмектесеміз және іс-шара күні дайындықтың әр бөлшегін бақылауда ұстаймыз."
            />
          </Reveal>
        </div>
      </section>

      {/* Section B — Что входит в организацию корпоратива */}
      <section className="toi-section toi-section--alt">
        <div className="container">
          <Reveal as="p" className="section-eyebrow"><T ru="СОСТАВ УСЛУГ" kz="ҚЫЗМЕТТЕР ҚҰРАМЫ" /></Reveal>
          <Reveal as="h2" className="section-title"><T ru="Что входит в организацию корпоратива" kz="Корпоративті ұйымдастыруға не кіреді" /></Reveal>

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
          <Reveal as="h2" className="section-title"><T ru="Планируете корпоратив в Алматы?" kz="Алматыда корпоратив жоспарлап жатырсыз ба?" /></Reveal>
          <Reveal as="p" className="section-desc">
            <T
              ru="Подберём площадку, ведущего, артистов и программу под формат вашей компании."
              kz="Компанияңыздың форматына сай алаң, жүргізуші, әртістер және бағдарлама таңдаймыз."
            />
          </Reveal>
          <div className="services__cta">
            <Link href="/#contacts" className="btn btn--gold">
              <T ru="Заказать корпоратив" kz="Корпоратив тапсырыс беру" />
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
