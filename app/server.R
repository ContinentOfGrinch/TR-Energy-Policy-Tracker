# =============================================================================
# server.R — reactive logic
# -----------------------------------------------------------------------------
# Pattern: filter ONCE in a reactive, let every observer and output consume that
# single result (§4). Recomputing the filter inside each output would run it
# four times per interaction and drift out of sync.
# =============================================================================

function(input, output, session) {

  # ===========================================================================
  # 1. THE SINGLE FILTERED DATASET
  # ===========================================================================
  # Everything downstream reads this. When the time slider arrives it plugs in
  # here and nothing else has to change.

  selected_facilities <- reactive({
    out <- facilities

    # An empty sector selection means "none", not "all". Silently showing
    # everything when the user has deselected everything would misrepresent
    # their own filter back to them.
    out <- out |> filter(sector %in% input$sectors)

    if (length(input$provinces) > 0) {
      out <- out |> filter(province_name_tr %in% input$provinces)
    }

    out
  })


  # ===========================================================================
  # 2. HEADLINE COUNTS
  # ===========================================================================

  count_for <- function(sector_key) {
    sum(selected_facilities()$sector == sector_key)
  }

  output$box_total <- renderValueBox({
    valueBox(
      value    = nrow(selected_facilities()),
      subtitle = paste0("Görüntülenen tesis (toplam ", N_FACILITIES, ")"),
      icon     = icon("industry"),
      color    = "black"
    )
  })

  output$box_steel <- renderValueBox({
    valueBox(count_for("iron-and-steel"), SECTOR_LABELS[["iron-and-steel"]],
             icon = icon("fire"), color = "red")
  })

  output$box_cement <- renderValueBox({
    valueBox(count_for("cement"), SECTOR_LABELS[["cement"]],
             icon = icon("cubes"), color = "blue")
  })

  output$box_aluminum <- renderValueBox({
    valueBox(count_for("aluminum"), SECTOR_LABELS[["aluminum"]],
             icon = icon("layer-group"), color = "orange")
  })

  output$map_title <- renderText({
    paste0("Türkiye SKDM Kapsamındaki Tesisler — ",
           nrow(selected_facilities()), " tesis")
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
      # Türkiye's extent, so the first frame is never a view of the Atlantic.
      fitBounds(lng1 = 25.6, lat1 = 35.8, lng2 = 44.8, lat2 = 42.1) |>
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
    } else {
      "#FFFFFF"
    }

    stroke_weight <- if (isTRUE(input$flag_uncertain)) {
      ifelse(df$geocode_quality == "within_province", 1, 3)
    } else {
      1
    }

    proxy |>
      addCircleMarkers(
        lng          = ~lon,
        lat          = ~lat,
        layerId      = ~facility_id,
        group        = "facilities",
        radius       = 7,
        fillColor    = ~unname(SECTOR_COLOURS[sector]),
        fillOpacity  = 0.85,
        color        = stroke_colour,
        weight       = stroke_weight,
        label        = ~facility_name_tr,
        popup        = ~paste0(
          "<strong>", facility_name_tr, "</strong><br/>",
          "<em>", unname(SECTOR_LABELS[sector]), "</em><br/><br/>",
          "<b>İşletmeci:</b> ", ifelse(is.na(operator_name), "—", operator_name), "<br/>",
          "<b>Teknoloji:</b> ", ifelse(is.na(technology), "—", technology), "<br/>",
          "<b>İl:</b> ", province_name_tr, " (", province_code, ")<br/>",
          "<b>İBBS-2:</b> ", nuts2_name_tr, " (", nuts2_code, ")<br/>",
          "<b>Konum:</b> ", unname(GEOCODE_LABELS[geocode_quality])
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
      return(tags$p(
        style = "color:#888;",
        "Ayrıntı için haritadan bir tesis seçin."
      ))
    }

    f <- facilities |> filter(facility_id == selected_id())

    row <- function(label, value) {
      tags$tr(
        tags$td(style = "padding:4px 10px 4px 0; color:#666; white-space:nowrap;", label),
        tags$td(style = "padding:4px 0; font-weight:600;", value)
      )
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
        style = "margin-top:14px; width:100%; font-size:13px;",
        row("İşletmeci",  ifelse(is.na(f$operator_name), "—", f$operator_name)),
        row("Teknoloji",  ifelse(is.na(f$technology), "—", f$technology)),
        row("İl",         paste0(f$province_name_tr, " (", f$province_code, ")")),
        row("İBBS-2",     paste0(f$nuts2_name_tr, " (", f$nuts2_code, ")")),
        row("Koordinat",  sprintf("%.4f, %.4f", f$lat, f$lon)),
        row("Kaynak",     paste0("Climate TRACE ", f$source_release)),
        row("Kaynak ID",  f$source_id)
      ),
      tags$div(
        style = paste0("margin-top:12px; padding:8px 10px; border-left:4px solid ",
                       GEOCODE_BADGE[[f$geocode_quality]], "; background:#fafafa;",
                       " font-size:12px;"),
        tags$b("Konum ataması: "),
        GEOCODE_LABELS[[f$geocode_quality]]
      )
    )
  })


  # ===========================================================================
  # 5. GEOCODE QUALITY SUMMARY
  # ===========================================================================
  # Surfacing this is a deliberate choice. A tool that shows 88 confident dots
  # and hides that 22 of them sit on or beyond a border is overstating what it
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
        tags$code("data/processed/facilities_geocode_report.csv"),
        " dosyasındadır."
      )
    )
  })


  # ===========================================================================
  # 6. SOURCES TAB
  # ===========================================================================

  output$sources_panel <- renderUI({
    tagList(
      tags$h4("Climate TRACE — tesis düzeyinde emisyon tahminleri"),
      tags$p(
        "Climate TRACE (climatetrace.org), ",
        tags$b("CC BY 4.0"), " lisansı altında. Sürüm: ",
        tags$code(SOURCE_RELEASE), ". Atıf, bu lisansın ",
        tags$b("hukuki koşuludur"), "; nezaket değildir."
      ),

      tags$h4("Natural Earth — idari sınırlar"),
      tags$p(
        "Made with Natural Earth (naturalearthdata.com), ",
        tags$b("kamu malı"), ". Tesis koordinatlarından il ve İBBS-2 bölgesi ",
        "türetmek için kullanılmıştır."
      ),

      tags$hr(),

      tags$h4("Kapsam dışı kalanlar"),
      tags$ul(
        tags$li(tags$b("Gübre: "),
                "Climate TRACE'te gübre üretimi alt sektörü bulunmamaktadır. ",
                "Benzer adlı ", tags$code("synthetic-fertilizer-application"),
                " tarımsal topraklardan salınan N₂O'yu kapsar; farklı bir ",
                "emisyon kaynağıdır ve SKDM'nin düzenlediği şey değildir."),
        tags$li(tags$b("Alüminyum PFC: "),
                "SKDM alüminyumda CO₂ ile birlikte PFC'leri de kapsar. ",
                "Climate TRACE PFC ülke paketi yayımlamamaktadır; bu nedenle ",
                "alüminyum maruziyeti eksik tahmin edilmektedir. Boşluk ",
                "doldurulmamış, işaretlenmiştir."),
        tags$li(tags$b("Elektrik ve hidrojen: "),
                "SKDM'nin altı mal grubundan ikisi kapsam dışıdır (v1 kararı).")
      ),

      tags$hr(),

      tags$h4("Lisanslar"),
      tags$ul(
        tags$li("Kaynak kod: MIT"),
        tags$li("Belgeler ve türetilmiş veri: CC BY 4.0"),
        tags$li("Kaynak veriler kendi lisanslarını korur")
      ),

      tags$p(
        style = "margin-top:16px; font-size:12px; color:#666;",
        "Tam atıf zinciri, sürüm etiketleri ve SHA-256 özetleri için: ",
        tags$code("data/processed/SOURCES.md")
      )
    )
  })
}
