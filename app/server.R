# =============================================================================
# server.R — reactive logic
# -----------------------------------------------------------------------------
# Pattern: filter ONCE in a reactive, let every observer and output consume that
# single result (§4). Recomputing the filter inside each output would run it
# six times per interaction and drift out of sync.
# =============================================================================

function(input, output, session) {

  # ===========================================================================
  # 1. THE SINGLE FILTERED DATASET
  # ===========================================================================
  # Everything downstream reads this. When the time slider arrives it plugs in
  # here and nothing else has to change.

  selected_facilities <- reactive({
    out <- facilities |>
      filter(asset_class %in% input$asset_classes,
             sector %in% input$sectors)

    if (length(input$provinces) > 0) {
      out <- out |> filter(province_name_tr %in% input$provinces)
    }

    if (isTRUE(input$only_captive)) {
      out <- out |> filter(!is.na(is_captive), is_captive)
    }

    out
  })


  # ===========================================================================
  # 2. HEADLINE COUNTS
  # ===========================================================================

  output$box_total <- renderValueBox({
    df <- selected_facilities()
    valueBox(
      value    = nrow(df),
      subtitle = paste0("Görüntülenen kayıt (toplam ", N_FACILITIES, ")"),
      icon     = icon("location-dot"),
      color    = "black"
    )
  })

  output$box_industrial <- renderValueBox({
    n <- sum(selected_facilities()$asset_class == "industrial")
    valueBox(n, "Sanayi tesisi — SKDM kapsamı",
             icon = icon("industry"), color = "red")
  })

  output$box_energy <- renderValueBox({
    n <- sum(selected_facilities()$asset_class == "energy")
    valueBox(n, "Enerji varlığı", icon = icon("bolt"), color = "blue")
  })

  output$box_year <- renderValueBox({
    df <- selected_facilities()
    pct <- if (nrow(df) == 0) 0 else
      round(100 * mean(!is.na(df$commissioning_year)))
    valueBox(paste0("%", pct), "Devreye giriş yılı bilinen",
             icon = icon("clock-rotate-left"), color = "olive")
  })

  output$map_title <- renderText({
    df <- selected_facilities()
    sites <- nrow(dplyr::distinct(df, lat, lon))
    paste0("Türkiye Karbon Atlası — ", nrow(df), " kayıt, ", sites, " ayrı konum")
  })


  # ===========================================================================
  # 3. MAP
  # ===========================================================================
  # Rendered ONCE with a fixed view; markers are updated through leafletProxy
  # (§4). Re-rendering the whole map on every filter change would reset the
  # user's pan and zoom, which is both slow and infuriating.

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      # CartoDB.Positron: neutral enough that facility points carry the colour.
      addProviderTiles(providers$CartoDB.Positron) |>
      # Türkiye's extent, widened north to include Black Sea offshore assets.
      fitBounds(lng1 = 25.6, lat1 = 35.8, lng2 = 44.8, lat2 = 43.2) |>
      addLegend(
        position = "bottomright",
        colors   = unname(SECTOR_COLOURS),
        labels   = unname(SECTOR_LABELS),
        title    = "Sektör",
        opacity  = 0.9
      )
  })

  observe({
    df <- selected_facilities()

    proxy <- leafletProxy("map", data = df) |> clearGroup("facilities")

    if (nrow(df) == 0) return(invisible(NULL))

    # Uncertain geocodes get a dark outline when the user asks for it. The
    # underlying flag is always present in the popup regardless.
    stroke_colour <- if (isTRUE(input$flag_uncertain)) {
      ifelse(df$geocode_quality == "within_province", "#FFFFFF", "#111111")
    } else "#FFFFFF"

    stroke_weight <- if (isTRUE(input$flag_uncertain)) {
      ifelse(df$geocode_quality == "within_province", 1, 3)
    } else 1

    # Industrial installations are the subject of the CBAM calculation, so they
    # are drawn slightly larger than the fleet that surrounds them.
    radius <- ifelse(df$asset_class == "industrial", 7, 5)

    proxy |>
      addCircleMarkers(
        lng          = ~lon,
        lat          = ~lat,
        layerId      = ~facility_id,
        group        = "facilities",
        radius       = radius,
        fillColor    = ~unname(SECTOR_COLOURS[sector]),
        fillOpacity  = 0.85,
        color        = stroke_colour,
        weight       = stroke_weight,
        label        = ~facility_name_tr,
        popup        = ~paste0(
          "<strong>", facility_name_tr, "</strong><br/>",
          "<em>", unname(SECTOR_LABELS[sector]), " · ",
          unname(ASSET_CLASS_LABELS[asset_class]), "</em><br/><br/>",
          "<b>İşletmeci:</b> ", ifelse(is.na(operator_name), "—", operator_name), "<br/>",
          "<b>Teknoloji:</b> ", ifelse(is.na(technology), "—", technology), "<br/>",
          "<b>Devreye giriş:</b> ",
          ifelse(is.na(commissioning_year), "bilinmiyor", commissioning_year), "<br/>",
          "<b>İl:</b> ", province_name_tr, " (", province_code, ")<br/>",
          "<b>Yükümlülük:</b> ", unname(LIABILITY_SHORT[liability_class])
        )
      )
  })


  # ===========================================================================
  # 4. SELECTED FACILITY DETAIL
  # ===========================================================================

  selected_id <- reactiveVal(NULL)

  observeEvent(input$map_marker_click, {
    selected_id(input$map_marker_click$id)
  })

  # A facility filtered out of view must not linger in the detail panel.
  observeEvent(selected_facilities(), {
    if (!is.null(selected_id()) &&
        !selected_id() %in% selected_facilities()$facility_id) {
      selected_id(NULL)
    }
  })

  output$facility_detail <- renderUI({
    if (is.null(selected_id())) {
      return(tags$p(style = "color:#888;",
                    "Ayrıntı için haritadan bir tesis seçin."))
    }

    f <- facilities |> filter(facility_id == selected_id())

    row <- function(label, value) {
      tags$tr(tags$td(style = "color:#666; white-space:nowrap;", label),
              tags$td(style = "font-weight:600;", value))
    }

    tagList(
      tags$h4(f$facility_name_tr, style = "margin-top:0;"),
      tags$span(
        style = paste0("background:", SECTOR_COLOURS[[f$sector]],
                       "; color:#fff; padding:2px 8px; border-radius:3px;",
                       " font-size:12px;"),
        SECTOR_LABELS[[f$sector]]
      ),

      tags$table(
        class = "kv", style = "margin-top:14px; width:100%;",
        row("Varlık sınıfı", ASSET_CLASS_LABELS[[f$asset_class]]),
        row("İşletmeci",     ifelse(is.na(f$operator_name), "—", f$operator_name)),
        row("Teknoloji",     ifelse(is.na(f$technology), "—", f$technology)),
        row("Devreye giriş",
            if (is.na(f$commissioning_year)) "bilinmiyor"
            else paste0(f$commissioning_year, " (", f$commissioning_source, ")")),
        row("İl",       paste0(f$province_name_tr, " (", f$province_code, ")")),
        row("İBBS-2",   paste0(f$nuts2_name_tr, " (", f$nuts2_code, ")")),
        row("Koordinat", sprintf("%.4f, %.4f", f$lat, f$lon)),
        row("Gaz tabanı", GAS_LABELS[[f$gas_basis]]),
        row("Kaynak",   paste0("Climate TRACE ", f$source_release)),
        row("Kaynak ID", f$source_id)
      ),

      # The field the whole merge turns on, spelled out rather than coded.
      tags$div(
        style = "margin-top:12px; padding:8px 10px; background:#f5f5f5; font-size:12px;",
        tags$b("Yükümlülük sınıfı: "),
        LIABILITY_LABELS[[f$liability_class]]
      ),

      if (!is.na(f$is_captive) && f$is_captive) {
        tags$div(
          style = paste0("margin-top:8px; padding:8px 10px; background:#FFF3E0;",
                         " border-left:4px solid #E8A33D; font-size:12px;"),
          tags$b("Kendi tesisini besleyen santral"),
          if (!is.na(f$captive_industry))
            paste0(" — ", f$captive_industry), ". ",
          "Şebekeyi beslemediği için şebeke emisyon faktörünün hem payından ",
          "hem paydasından çıkarılır."
        )
      },

      tags$div(
        style = paste0("margin-top:12px; padding:8px 10px; border-left:4px solid ",
                       GEOCODE_BADGE[[f$geocode_quality]], "; background:#fafafa;",
                       " font-size:12px;"),
        tags$b("Konum ataması: "), GEOCODE_LABELS[[f$geocode_quality]]
      )
    )
  })


  # ===========================================================================
  # 5. QUALITY SUMMARIES
  # ===========================================================================
  # Surfacing these is a deliberate choice. A tool that shows 300 confident dots
  # and hides that 80 of them sit on or beyond a border is overstating what it
  # knows (§8.4).

  output$geocode_summary <- renderUI({
    df <- selected_facilities()
    if (nrow(df) == 0) return(tags$p("Seçili tesis yok."))

    tally <- df |> count(geocode_quality, name = "n")

    tagList(
      tags$table(
        style = "width:100%; font-size:13px;",
        lapply(seq_len(nrow(tally)), function(i) {
          q <- tally$geocode_quality[i]
          tags$tr(
            tags$td(style = paste0("padding:5px 0; border-left:4px solid ",
                                   GEOCODE_BADGE[[q]], "; padding-left:8px;"),
                    GEOCODE_LABELS[[q]]),
            tags$td(style = "text-align:right; font-weight:600;", tally$n[i])
          )
        })
      ),
      tags$p(
        style = "margin-top:10px; font-size:12px; color:#666;",
        "İl sınırları Natural Earth 10m katmanından türetilmiştir. Bu ",
        "çözünürlük, il sınırına çok yakın veya kıyı dolgusu üzerindeki ",
        "tesisleri kesin olarak ayırt edemez. Tesis bazında mesafeler ",
        tags$code("data/processed/facilities_geocode_report.csv"), " dosyasındadır."
      )
    )
  })

  output$commissioning_summary <- renderUI({
    df <- selected_facilities()
    if (nrow(df) == 0) return(tags$p("Seçili tesis yok."))

    by_class <- df |>
      group_by(asset_class) |>
      summarise(n = n(), known = sum(!is.na(commissioning_year)),
                .groups = "drop")

    tagList(
      tags$table(
        style = "width:100%; font-size:13px;",
        lapply(seq_len(nrow(by_class)), function(i) {
          tags$tr(
            tags$td(ASSET_CLASS_LABELS[[by_class$asset_class[i]]]),
            tags$td(style = "text-align:right; font-weight:600;",
                    paste0(by_class$known[i], " / ", by_class$n[i]))
          )
        })
      ),
      tags$p(
        style = "margin-top:10px; font-size:12px; color:#666;",
        "Devreye giriş yılı Global Energy Monitor'den, koordinat yakınlığıyla ",
        "eşleştirilerek alınmıştır — Climate TRACE 2021'de başlar ve bu alanı ",
        "taşımaz. Yılı bilinmeyen tesisler, 2021 öncesi filo animasyonundan ",
        tags$b("görünür şekilde dışlanmalıdır"), "; her zaman var oldukları ",
        "varsayılmamalıdır."
      )
    )
  })


  # ===========================================================================
  # 6. GRID INTENSITY
  # ===========================================================================
  # Three estimates, one of them deliberately wrong. Publishing only the chosen
  # figure would hide why it was chosen (§7).

  output$grid_panel <- renderUI({
    if (is.null(grid_intensity)) {
      return(tags$p(
        "Şebeke yoğunluğu verisi henüz üretilmedi. Çalıştırın: ",
        tags$code("Rscript scripts/01d_fetch_ember.R")))
    }

    g <- grid_intensity[grid_intensity$year >= 2021, ]

    tagList(
      tags$p(
        "Sanayi tesislerinin ", tags$b("dolaylı"), " emisyonu, tükettikleri ",
        "elektriğin karbon yoğunluğuyla çarpılarak bulunur. O yoğunluk için üç ",
        "bağımsız tahmin var ve aradaki fark başlı başına bir sonuçtur."
      ),

      tags$table(
        style = "width:100%; margin-top:12px; font-size:13px; border-collapse:collapse;",
        tags$thead(tags$tr(
          lapply(c("Yıl", "Ember", "Climate TRACE", "CT filosu (naif)",
                   "CT kapsaması", "Yenilenebilir"),
                 function(h) tags$th(style = "text-align:left; padding:6px; border-bottom:2px solid #ddd;", h))
        )),
        tags$tbody(lapply(seq_len(nrow(g)), function(i) {
          tags$tr(
            tags$td(style = "padding:6px; border-bottom:1px solid #eee;", g$year[i]),
            tags$td(style = "padding:6px; border-bottom:1px solid #eee; font-weight:600;",
                    round(g$ember_g_per_kwh[i])),
            tags$td(style = "padding:6px; border-bottom:1px solid #eee; font-weight:600;",
                    round(g$ct_reported_g_per_kwh[i])),
            tags$td(style = "padding:6px; border-bottom:1px solid #eee; color:#C0392B;",
                    round(g$ct_naive_g_per_kwh[i])),
            tags$td(style = "padding:6px; border-bottom:1px solid #eee;",
                    paste0("%", round(100 * g$ct_coverage_share[i]))),
            tags$td(style = "padding:6px; border-bottom:1px solid #eee;",
                    paste0("%", round(100 * g$renewable_share[i])))
          )
        }))
      ),
      tags$p(style = "font-size:12px; color:#666; margin-top:6px;",
             "gCO₂/kWh"),

      tags$div(
        style = paste0("margin-top:16px; padding:10px 14px; background:#FDECEA;",
                       " border-left:4px solid #C0392B; font-size:13px;"),
        tags$b("Üçüncü sütun neden yanlış? "),
        "Climate TRACE'in Türkiye elektrik kütüğü yalnızca yanma tesislerini ",
        "içeriyor — hidro, rüzgâr, güneş, jeotermal ve nükleer yok. Ulusal ",
        "üretimin yaklaşık yarısını görüyor ve görmediği yarı neredeyse tam ",
        "olarak yenilenebilir olan yarı. Aritmetik doğru, payda eksik. Sütun ",
        "silinmedi çünkü birinin ileride aynı hesabı yapıp doğru sanmasını ",
        "engellemek, hatayı göstermekten geçiyor."
      ),

      tags$p(style = "margin-top:14px; font-size:13px;",
             tags$b("İlk iki sütun bağımsız yöntemlerden geliyor ve uyuşuyor. "),
             "Hangisinin hesaba gireceği ve kendi tesisini besleyen santrallerin ",
             "nasıl netleştirileceği metodolojik bir karardır; ",
             tags$code("policies/grid_emission_factor.json"), " içinde ",
             tags$code("selection.chosen"), " bilerek boş bırakılmıştır.")
    )
  })


  # ===========================================================================
  # 7. SOURCES TAB
  # ===========================================================================

  output$sources_panel <- renderUI({
    tagList(
      tags$h4("Climate TRACE — tesis düzeyinde emisyon tahminleri"),
      tags$p("Climate TRACE (climatetrace.org), ", tags$b("CC BY 4.0"),
             " lisansı altında. Sürüm: ", tags$code(SOURCE_RELEASE), "."),

      tags$h4("Global Energy Monitor — devreye giriş yılları ve filo"),
      tags$p("Global Energy Monitor, ", tags$b("CC BY 4.0"),
             ". Global Integrated Power Tracker ve Global Coal Mine Tracker. ",
             "Veriler Türkiye'ye filtrelenmiş, Climate TRACE kayıtlarıyla ",
             "koordinat yakınlığıyla eşleştirilmiş ve koordinatlardan il ile ",
             "İBBS-2 bölgesi türetilmiştir."),

      tags$h4("Ember — ulusal üretim ve şebeke yoğunluğu"),
      tags$p("Ember (Ember Energy Research CIC), ", tags$b("CC BY 4.0"),
             ". Yakıt bazlı yıllık üretim serisi, 2000'den itibaren."),

      tags$h4("Natural Earth — idari sınırlar"),
      tags$p("Made with Natural Earth, ", tags$b("kamu malı"), "."),

      tags$p(style = "font-size:12px; color:#666;",
             "Atıf, CC BY 4.0'ın ", tags$b("hukuki koşuludur"),
             "; nezaket değildir. Hiçbir kaynak bu projeyi onaylamamaktadır."),

      tags$hr(),

      tags$h4("Kapsam dışı kalanlar"),
      tags$ul(
        tags$li(tags$b("Gübre: "),
                "Climate TRACE'te gübre üretimi alt sektörü yoktur. Benzer adlı ",
                tags$code("synthetic-fertilizer-application"),
                " tarımsal topraklardan salınan N₂O'yu kapsar — farklı bir ",
                "emisyon kaynağıdır ve SKDM'nin düzenlediği şey değildir."),
        tags$li(tags$b("Alüminyum PFC: "),
                "SKDM alüminyumda CO₂ ile birlikte PFC'leri de kapsar. PFC ülke ",
                "paketi yayımlanmadığı için alüminyum maruziyeti eksik tahmin ",
                "edilmektedir. Boşluk doldurulmamış, işaretlenmiştir."),
        tags$li(tags$b("Yenilenebilir santraller: "),
                "Climate TRACE'in elektrik kütüğünde hidro, rüzgâr, güneş, ",
                "jeotermal ve nükleer yoktur. Bu haritadaki enerji varlıkları ",
                "yalnızca yanma tesisleri, kömür ocakları ve petrol-gaz ",
                "tesisleridir."),
        tags$li(tags$b("Elektrik ve hidrojen: "),
                "SKDM'nin altı mal grubundan ikisi kapsam dışıdır. Elektrik ",
                tags$i("üretim varlıkları"), " kapsamdadır; elektrik ",
                tags$i("ithal bir SKDM malı"), " olarak kapsam dışıdır.")
      ),

      tags$hr(),

      tags$h4("Lisanslar"),
      tags$ul(
        tags$li("Kaynak kod: MIT"),
        tags$li("Belgeler ve türetilmiş veri: CC BY 4.0"),
        tags$li("Kaynak veriler kendi lisanslarını korur")
      ),

      tags$p(style = "margin-top:16px; font-size:12px; color:#666;",
             "Tam atıf zinciri, sürüm etiketleri ve SHA-256 özetleri için: ",
             tags$code("data/processed/SOURCES.md"), ", ",
             tags$code("SOURCES_GEM.md"), ", ",
             tags$code("SOURCES_EMBER.md"))
    )
  })
}
