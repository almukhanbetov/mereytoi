package seed

import (
	"log"

	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type categorySeed struct {
	Slug   string
	NameRu string
	NameKz string
	Pos    int
	Items  []models.Listing
}

// Run seeds the 5 fixed categories and a handful of example listings in
// each, if the categories table is empty. Safe to call on every startup.
func Run(database *gorm.DB) {
	var count int64
	database.Model(&models.Category{}).Count(&count)
	if count > 0 {
		return
	}

	data := []categorySeed{
		{
			Slug: "venues", NameRu: "Рестораны и локации", NameKz: "Мейрамханалар мен локациялар", Pos: 1,
			Items: []models.Listing{
				{NameRu: "Almaty Grand Hall", NameKz: "Almaty Grand Hall", City: "Алматы", Phone: "+7 700 111 22 33", Price: 12000, MinGuests: 100, MaxGuests: 300, Rating: 4.8, Emoji: "🏛️", ColorFrom: "#3a1420", ColorTo: "#d4af6a", DescriptionRu: "Банкетный зал на 500 гостей в центре города.", DescriptionKz: "Қала орталығында 500 қонаққа арналған банкет залы."},
				{NameRu: "Nomad Banquet House", NameKz: "Nomad Banquet House", City: "Астана", Phone: "+7 700 222 33 44", Price: 15000, MinGuests: 80, MaxGuests: 250, Rating: 4.6, Emoji: "🎪", ColorFrom: "#142a3a", ColorTo: "#f3d9a4", DescriptionRu: "Современный банкетный дом с панорамными окнами.", DescriptionKz: "Панорамалық терезелері бар заманауи банкет үйі."},
				{NameRu: "Shymkent Saraishyq", NameKz: "Шымкент Сарайшық", City: "Шымкент", Phone: "+7 700 333 44 55", Price: 9000, MinGuests: 50, MaxGuests: 200, Rating: 4.5, Emoji: "🕌", ColorFrom: "#20301f", ColorTo: "#d4af6a", DescriptionRu: "Зал в национальном стиле для тоев и юбилеев.", DescriptionKz: "Той мен мерейтойларға арналған ұлттық стильдегі зал."},
			},
		},
		{
			Slug: "hosts", NameRu: "Ведущие", NameKz: "Жүргізушілер", Pos: 2,
			Items: []models.Listing{
				{NameRu: "Ерлан Ахметов", NameKz: "Ерлан Ахметов", City: "Алматы", Phone: "+7 701 111 22 33", Price: 80000, Rating: 4.9, Emoji: "🎙️", ColorFrom: "#3a1420", ColorTo: "#f3d9a4", DescriptionRu: "Ведущий с 10-летним опытом, свадьбы и юбилеи.", DescriptionKz: "10 жылдық тәжірибесі бар жүргізуші, той және мерейтойлар."},
				{NameRu: "Динара Касымова", NameKz: "Динара Қасымова", City: "Астана", Phone: "+7 701 222 33 44", Price: 90000, Rating: 5.0, Emoji: "🎤", ColorFrom: "#1f1430", ColorTo: "#d4af6a", DescriptionRu: "Ведущая на двух языках, авторские сценарии.", DescriptionKz: "Екі тілде жүргізуші, авторлық сценарийлер."},
				{NameRu: "Асхат Жумабаев", NameKz: "Асхат Жұмабаев", City: "Шымкент", Phone: "+7 701 333 44 55", Price: 70000, Rating: 4.7, Emoji: "🎭", ColorFrom: "#142a3a", ColorTo: "#d4af6a", DescriptionRu: "Энергичный ведущий, интерактив с гостями.", DescriptionKz: "Қонақтармен интерактив жасайтын белсенді жүргізуші."},
			},
		},
		{
			Slug: "shows", NameRu: "Шоу-программы", NameKz: "Шоу-бағдарламалар", Pos: 3,
			Items: []models.Listing{
				{NameRu: "Файер-шоу «Отты билер»", NameKz: "«Отты билер» файер-шоуы", City: "Алматы", Phone: "+7 702 111 22 33", Price: 60000, Rating: 4.8, Emoji: "🔥", ColorFrom: "#3a1420", ColorTo: "#d4af6a", DescriptionRu: "Яркое огненное шоу для вечерней программы.", DescriptionKz: "Кешкі бағдарламаға арналған жарқын от-шоу."},
				{NameRu: "Лазерное шоу-инсталляция", NameKz: "Лазерлік шоу-инсталляция", City: "Астана", Phone: "+7 702 222 33 44", Price: 95000, Rating: 4.6, Emoji: "✨", ColorFrom: "#1f1430", ColorTo: "#f3d9a4", DescriptionRu: "Современное лазерное шоу под живую музыку.", DescriptionKz: "Тірі музыка астында заманауи лазерлік шоу."},
				{NameRu: "Фольклорный ансамбль «Салтанат»", NameKz: "«Салтанат» фольклорлық ансамблі", City: "Түркістан", Phone: "+7 702 333 44 55", Price: 75000, Rating: 4.9, Emoji: "🪕", ColorFrom: "#20301f", ColorTo: "#d4af6a", DescriptionRu: "Национальные танцы и живая музыка.", DescriptionKz: "Ұлттық билер мен тірі музыка."},
			},
		},
		{
			Slug: "artists", NameRu: "Артисты и исполнители", NameKz: "Әртістер мен орындаушылар", Pos: 4,
			Items: []models.Listing{
				{NameRu: "Группа «Yenlik Band»", NameKz: "«Yenlik Band» тобы", City: "Алматы", Phone: "+7 703 111 22 33", Price: 150000, Rating: 4.8, Emoji: "🎸", ColorFrom: "#3a1420", ColorTo: "#f3d9a4", DescriptionRu: "Живая кавер-группа, широкий репертуар.", DescriptionKz: "Тірі кавер-тобы, кең репертуар."},
				{NameRu: "Скрипичный квартет «Аруна»", NameKz: "«Аруна» скрипка квартеті", City: "Астана", Phone: "+7 703 222 33 44", Price: 120000, Rating: 4.9, Emoji: "🎻", ColorFrom: "#142a3a", ColorTo: "#d4af6a", DescriptionRu: "Классическая и современная музыка для церемонии.", DescriptionKz: "Салтанат рәсіміне классикалық және заманауи музыка."},
				{NameRu: "DJ Nomad", NameKz: "DJ Nomad", City: "Шымкент", Phone: "+7 703 333 44 55", Price: 100000, Rating: 4.7, Emoji: "🎧", ColorFrom: "#1f1430", ColorTo: "#d4af6a", DescriptionRu: "DJ-сет для вечерней части тоя.", DescriptionKz: "Тойдың кешкі бөлігіне арналған DJ-сет."},
			},
		},
		{
			Slug: "stars", NameRu: "Звёзды эстрады", NameKz: "Эстрада жұлдыздары", Pos: 5,
			Items: []models.Listing{
				{NameRu: "Айгуль Nova", NameKz: "Айгүл Nova", City: "Алматы", Phone: "+7 704 111 22 33", Price: 500000, Rating: 4.9, Emoji: "⭐", ColorFrom: "#7a1f2b", ColorTo: "#d4af6a", DescriptionRu: "Популярная эстрадная исполнительница, выступление 30 минут.", DescriptionKz: "Танымал эстрада әншісі, 30 минуттық өнер көрсету."},
				{NameRu: "Dana Jibek", NameKz: "Dana Jibek", City: "Астана", Phone: "+7 704 222 33 44", Price: 450000, Rating: 4.8, Emoji: "🌟", ColorFrom: "#1f1430", ColorTo: "#f3d9a4", DescriptionRu: "Звезда эстрады, живой вокал и танцевальная шоу-программа.", DescriptionKz: "Эстрада жұлдызы, тірі вокал және би-шоу бағдарламасы."},
				{NameRu: "Samal Stars", NameKz: "Samal Stars", City: "Шымкент", Phone: "+7 704 333 44 55", Price: 400000, Rating: 4.7, Emoji: "🎇", ColorFrom: "#142a3a", ColorTo: "#d4af6a", DescriptionRu: "Молодая звезда эстрады, хиты последних лет.", DescriptionKz: "Жас эстрада жұлдызы, соңғы жылдардың хиттері."},
			},
		},
	}

	for _, c := range data {
		category := models.Category{Slug: c.Slug, NameRu: c.NameRu, NameKz: c.NameKz, Position: c.Pos}
		if err := database.Create(&category).Error; err != nil {
			log.Printf("seed: failed to create category %s: %v", c.Slug, err)
			continue
		}
		for _, item := range c.Items {
			item.CategoryID = category.ID
			if err := database.Create(&item).Error; err != nil {
				log.Printf("seed: failed to create listing %s: %v", item.NameRu, err)
			}
		}
	}

	log.Println("seed: categories and sample listings created")
}
