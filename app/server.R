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
  # Everything downstream reads this. Two reactives, layered: the register
  # filter, then the year join. Splitting them means the map's geometry does not
  # recompute when only the year changes, and the year join does not recompute
  # when only a province is deselected.

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

  # Debounced: dragging the slider fires an event per pixel, and each one would
  # otherwise redraw 300 markers and a plot. 250 ms is short enough to feel
  # immediate and long enough to collapse a drag into one redraw (§4).
  current_year <- reactive({
    if (is.null(input$year)) DEFAULT_YEAR else input$year
  }) |> debounce(250)

  # The selected facilities joined to the selected year. A left join, not an
  # inner one: a facility with no panel row for that year must still appear on
  # the map with its emissions unknown, rather than silently vanishing and
  # making the fleet look smaller than it is.
  selected_year_data <- reactive({
    df <- selected_facilities()
    if (is.null(panel) || nrow(df) == 0) {
      return(df |> mutate(emissions_reported_t = NA_real_,
                          production_activity  = NA_real_,
                          emission_intensity   = NA_real_,
                          months_covered       = NA_integer_,
                          value_type           = NA_character_,
                          status               = NA_character_,
                          confidence_emissions = NA_character_))
    }

    yr <- current_year()

    df |>
      left_join(
        panel |>
          filter(year == yr) |>
          select(facility_id, emissions_reported_t, production_activity,
                 emission_intensity, months_covered, value_type, status,
                 confidence_emissions),
        by = "facility_id"
      )
  })

  # Is the selected year a projection? Asked once, used by several outputs.
  year_is_projected <- reactive({
    !is.null(panel) && current_year() %in%
      setdiff(PANEL_YEARS, OBSERVED_YEARS)
  })


  # ===========================================================================
  # 2. THE YEAR'S STATUS
  # ===========================================================================
  # Two outputs, both driven by the same question: can this year be read the way
  # a year is normally read? They stay silent when it can, so that when they
  # speak they are still noticed.

  output$year_status <- renderUI({
    yr <- current_year()
    vt <- if (year_is_projected()) "projected" else "observed"

    badge_bg <- if (vt == "projected") "#7B1FA2" else "#4C9A2A"
    depth    <- year_depth_note(yr)

    tags$div(
      style = "margin-top:-8px; font-size:12px; color:#c8d0d4;",
      tags$span(class = "yr-badge",
                style = paste0("background:", badge_bg, "; color:#fff;"),
                unname(VALUE_TYPE_LABELS[vt])),
      if (!is.null(depth)) {
        tags$span(style = "margin-left:6px; color:#E8A33D;", depth)
      }
    )
  })

  output$year_warning <- renderUI({
    yr    <- current_year()
    depth <- year_depth_note(yr)
    out   <- tagList()

    # A projection rendered like an observation is the single most misleading
    # thing this interface could do (§5), so it is stated in words, not colour.
    if (year_is_projected()) {
      out <- tagList(out, tags$div(
        class = "projection-note",
        tags$strong(yr, " bir KESTİRİM yılıdır."),
        " Climate TRACE bu yıl için gözlem değil kestirim yayımlıyor. ",
        "Haritadaki noktalar kesik çizgili ve soluk çizilir. ",
        tags$b("Gerçekleşmiş rakam olarak okunmamalıdır.")
      ))
    }

    # The 5-versus-6 month asymmetry. Not a footnote: a bar labelled 2026 beside
    # another labelled 2026 asserts they are comparable, and here they are not.
    if (!is.null(depth)) {
      out <- tagList(out, tags$div(
        class = "partial-note",
        tags$strong(yr, " kısmi bir yıldır — ", depth, "."),
        " İki popülasyonun bu yılı ", tags$b("aynı uzunlukta değildir"),
        " ve doğrudan karşılaştırılamaz. Kısmi yıl, tam yıla ",
        tags$b("ölçeklenerek tamamlanmaz"), ": çimento üretimi mevsimseldir, ",
        "12/5 çarpanı rastgele değil sistematik sapma üretir."
      ))
    }

    out
  })


  # ===========================================================================
  # 3. HEADLINE FIGURES
  # ===========================================================================
  # The two populations get their own box each, because their figures are in
  # different gases and a combined total would be meaningless (§6).

  fmt_mt <- function(t) {
    if (all(is.na(t))) return("—")
    paste0(format(round(sum(t, na.rm = TRUE) / 1e6, 1), nsmall = 1), " Mt")
  }

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
    df <- selected_year_data() |> filter(asset_class == "industrial")
    valueBox(
      value    = fmt_mt(df$emissions_reported_t),
      subtitle = paste0("Sanayi CO₂ — ", nrow(df), " tesis, ", current_year()),
      icon     = icon("industry"), color = "red"
    )
  })

  output$box_energy <- renderValueBox({
    df <- selected_year_data() |> filter(asset_class == "energy")
    valueBox(
      value    = fmt_mt(df$emissions_reported_t),
      subtitle = paste0("Enerji CO₂e — ", nrow(df), " varlık, ", current_year()),
      icon     = icon("bolt"), color = "blue"
    )
  })

  # Deliberately NOT a CBAM cost. The box says what is missing rather than
  # showing a zero that would be read as "no exposure".
  output$box_year <- renderValueBox({
    valueBox(
      value    = "—",
      subtitle = "SKDM maruziyeti — hesap henüz yok",
      icon     = icon("hourglass-half"), color = "olive"
    )
  })

  output$map_title <- renderText({
    df    <- selected_facilities()
    sites <- nrow(dplyr::distinct(df, lat, lon))
    paste0("Türkiye Karbon Atlası — ", current_year(), " · ",
           nrow(df), " kayıt, ", sites, " ayrı konum")
  })


  # ===========================================================================
  # 3. MAP
  # ===========================================================================
  # Rendered ONCE with a fixed view; markers are updated through leafletProxy
  # (§4). Re-rendering the whole map on every filter change would reset the
  # user's pan and zoom, which is both slow and infuriating.

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(
      preferCanvas = TRUE,
      # The atlas is about Türkiye. Letting the view drift into the Atlantic
      # makes it look unfinished and invites the reader to look for data that
      # was never claimed. maxBounds pins panning; minZoom stops the country
      # shrinking to a dot. A world view belongs to a future trade layer with
      # its own map, not to this one.
      minZoom = 5, maxZoom = 14
    )) |>
      # CartoDB.Positron: neutral enough that facility points carry the colour.
      addProviderTiles(providers$CartoDB.Positron) |>
      fitBounds(lng1 = MAP_BOUNDS$lng1, lat1 = MAP_BOUNDS$lat1,
                lng2 = MAP_BOUNDS$lng2, lat2 = MAP_BOUNDS$lat2) |>
      # A little slack beyond the data so coastal facilities are not pinned to
      # the very edge of the viewport.
      setMaxBounds(lng1 = MAP_BOUNDS$lng1 - 1.5, lat1 = MAP_BOUNDS$lat1 - 1.0,
                   lng2 = MAP_BOUNDS$lng2 + 1.5, lat2 = MAP_BOUNDS$lat2 + 1.0) |>
      addLegend(
        position = "bottomright",
        colors   = unname(SECTOR_COLOURS),
        labels   = unname(SECTOR_LABELS),
        title    = "Sektör",
        opacity  = 0.9
      )
  })

  observe({
    df <- selected_year_data()
    yr <- current_year()

    proxy <- leafletProxy("map", data = df) |> clearGroup("facilities")

    if (nrow(df) == 0) return(invisible(NULL))

    projected <- year_is_projected()

    # Uncertain geocodes get a dark outline when the user asks for it. The
    # underlying flag is always present in the popup regardless.
    stroke_colour <- if (isTRUE(input$flag_uncertain)) {
      ifelse(df$geocode_quality == "within_province", "#FFFFFF", "#111111")
    } else "#FFFFFF"

    stroke_weight <- if (isTRUE(input$flag_uncertain)) {
      ifelse(df$geocode_quality == "within_province", 1, 3)
    } else 1

    # AREA scales with emissions, so radius takes the square root. Scaling the
    # radius directly would make a plant twice as dirty look four times as big,
    # which is the standard way a bubble map lies.
    #
    # The two populations are scaled SEPARATELY, because their figures are in
    # different gases and a shared scale would invite exactly the comparison
    # §6 forbids. Within each half, area is comparable; across them, only
    # position is.
    scaled_radius <- function(v, cls) {
      out <- rep(NA_real_, length(v))
      for (k in unique(cls)) {
        i <- cls == k
        top <- suppressWarnings(max(v[i], na.rm = TRUE))
        if (!is.finite(top) || top <= 0) { out[i] <- 4; next }
        out[i] <- 4 + 11 * sqrt(pmax(v[i], 0) / top)
      }
      # A facility with no emissions figure for this year still has to be
      # visible and must not be mistaken for a zero-emission one.
      out[is.na(out)] <- 3
      out
    }

    radius <- scaled_radius(df$emissions_reported_t, df$asset_class)

    # A projection is drawn dashed and desaturated. Never identical to an
    # observation (§5) — colour alone is not enough, so the outline changes too.
    dash <- if (projected) "3,4" else NULL
    fill_opacity <- if (projected) 0.45 else 0.85

    proxy |>
      addCircleMarkers(
        lng          = ~lon,
        lat          = ~lat,
        layerId      = ~facility_id,
        group        = "facilities",
        radius       = radius,
        fillColor    = ~unname(SECTOR_COLOURS[sector]),
        fillOpacity  = fill_opacity,
        color        = stroke_colour,
        weight       = stroke_weight,
        dashArray    = dash,
        label        = ~paste0(facility_name_tr, " — ",
                               ifelse(is.na(emissions_reported_t), "veri yok",
                                      paste0(format(round(emissions_reported_t / 1000, 1),
                                                    nsmall = 1), " kt"))),
        popup        = ~paste0(
          "<strong>", facility_name_tr, "</strong><br/>",
          "<em>", unname(SECTOR_LABELS[sector]), " · ",
          unname(ASSET_CLASS_LABELS[asset_class]), "</em><br/><br/>",

          "<b>", yr, " emisyonu:</b> ",
          ifelse(is.na(emissions_reported_t), "veri yok",
                 paste0(format(round(emissions_reported_t / 1000, 1), nsmall = 1),
                        " kt ", unname(GAS_LABELS[gas_basis]))),
          ifelse(is.na(value_type), "",
                 paste0(" <span style='color:",
                        ifelse(value_type == "projected", "#7B1FA2", "#4C9A2A"),
                        ";'>(", unname(VALUE_TYPE_LABELS[value_type]), ")</span>")),
          "<br/>",

          "<b>Üretim:</b> ",
          ifelse(is.na(production_activity), "yayımlanmıyor",
                 format(round(production_activity), big.mark = ".",
                        decimal.mark = ",")),
          "<br/>",
          "<b>Yoğunluk:</b> ",
          ifelse(is.na(emission_intensity), "hesaplanamıyor",
                 format(round(emission_intensity, 3), nsmall = 3)),
          "<br/>",
          "<b>Güven (emisyon):</b> ",
          ifelse(is.na(confidence_emissions), "—", confidence_emissions),
          "<br/><br/>",

          "<b>İşletmeci:</b> ", ifelse(is.na(operator_name), "—", operator_name), "<br/>",
          "<b>Teknoloji:</b> ", ifelse(is.na(technology), "—", technology), "<br/>",
          "<b>Devreye giriş:</b> ",
          ifelse(is.na(commissioning_year), "bilinmiyor", commissioning_year), "<br/>",
          "<b>İl:</b> ", province_name_tr, " (", province_code, ")<br/>",
          "<b>Yükümlülük:</b> ", unname(LIABILITY_SHORT[liability_class])
        )
      )
  })


  # ---------------------------------------------------------------------------
  # Renewable fleet — a separate register, drawn as context
  # ---------------------------------------------------------------------------
  # Off by default and in its own layer group, because these plants are not part
  # of the modelled population. They emit essentially nothing, they come from
  # GEM rather than Climate TRACE, and they are here to answer one question:
  # where the rest of Türkiye's generation is. Drawn smaller and semi-
  # transparent so they read as background against the emitting facilities.

  observe({
    proxy <- leafletProxy("map") |> clearGroup("fleet")

    if (is.null(fleet_renewables) || !isTRUE(input$show_fleet)) {
      return(invisible(NULL))
    }

    df <- fleet_renewables
    if (length(input$provinces) > 0) {
      df <- df |> filter(province_name_tr %in% input$provinces)
    }
    if (nrow(df) == 0) return(invisible(NULL))

    proxy |>
      addCircleMarkers(
        data        = df,
        lng         = ~lon,
        lat         = ~lat,
        group       = "fleet",
        # Radius scales with capacity so a 600 MW dam does not read like a 1 MW
        # rooftop array, but stays small enough to sit behind the facilities.
        radius      = ~pmax(2, pmin(9, sqrt(pmax(capacity_mw, 0)) / 3)),
        fillColor   = ~unname(FLEET_COLOURS[fuel_type]),
        fillOpacity = 0.55,
        color       = "#FFFFFF",
        weight      = 0.5,
        label       = ~plant_name,
        popup       = ~paste0(
          "<strong>", plant_name, "</strong><br/>",
          "<em>", unname(FLEET_LABELS[fuel_type]), " — yenilenebilir filo</em>",
          "<br/><br/>",
          "<b>Kapasite:</b> ", round(capacity_mw, 1), " MW",
          ifelse(units > 1, paste0(" (", units, " ünite)"), ""), "<br/>",
          "<b>Devreye giriş:</b> ",
          ifelse(is.na(commissioning_year), "bilinmiyor", commissioning_year), "<br/>",
          "<b>İl:</b> ", province_name_tr, "<br/>",
          "<b>Kaynak:</b> Global Energy Monitor<br/><br/>",
          "<span style='color:#666;'>Bu tesis modellenen 300 kaydın parçası ",
          "değildir. Emisyon üretmediği için emisyon tablolarında yer almaz; ",
          "haritada, Climate TRACE'in elektrik kütüğünün göremediği üretimi ",
          "göstermek için bulunur.</span>"
        )
      )
  })


  # ===========================================================================
  # 3b. THE SERIES
  # ===========================================================================
  # What a single year cannot show. Base graphics deliberately: neither ggplot2
  # nor plotly is in renv.lock, and adding a dependency to draw six points would
  # be a poor trade.
  #
  # The two populations are drawn on SEPARATE axes — left for industrial CO2,
  # right for energy CO2e — because they are different gases. Sharing one axis
  # would put them in the same visual space and invite the sum that §6 forbids.

  trend_series <- reactive({
    req(!is.null(panel))
    ids <- selected_facilities()$facility_id
    if (length(ids) == 0) return(NULL)

    panel |>
      filter(facility_id %in% ids) |>
      group_by(gas_basis, year) |>
      summarise(mt         = sum(emissions_reported_t, na.rm = TRUE) / 1e6,
                months     = first(months_covered),
                value_type = first(value_type),
                .groups = "drop")
  })

  output$trend_plot <- renderPlot({
    s <- trend_series()
    if (is.null(s) || nrow(s) == 0) {
      plot.new()
      text(0.5, 0.5, "Seçili tesis yok", col = "#888", cex = 1.1)
      return(invisible(NULL))
    }

    op <- par(mar = c(3.2, 4.0, 0.6, 4.0), cex.axis = 0.8, cex.lab = 0.85,
              mgp = c(2.3, 0.6, 0), tcl = -0.25, las = 1)
    on.exit(par(op), add = TRUE)

    yrs <- sort(unique(s$year))

    draw_one <- function(basis, colour, side, first) {
      d <- s[s$gas_basis == basis, ]
      if (nrow(d) == 0) return(invisible(NULL))
      d <- d[order(d$year), ]

      if (first) {
        plot(d$year, d$mt, type = "n", xlab = "", ylab = "",
             xlim = range(yrs), ylim = c(0, max(d$mt) * 1.15),
             xaxt = "n", yaxt = "n", bty = "n")
        axis(1, at = yrs, labels = yrs, col = "#ccc", col.axis = "#555")
        grid(nx = NA, ny = NULL, col = "#eee", lty = 1)
      } else {
        par(new = TRUE)
        plot(d$year, d$mt, type = "n", xlab = "", ylab = "",
             xlim = range(yrs), ylim = c(0, max(d$mt) * 1.15),
             axes = FALSE, bty = "n")
      }
      axis(side, col = colour, col.axis = colour)
      mtext(unname(GAS_LABELS[basis]), side = side, line = 2.4,
            col = colour, cex = 0.8)

      # Observed and projected are drawn as two segments of one line: solid up
      # to the last observed year, dashed beyond it. The join point is repeated
      # in both so the line does not break.
      obs  <- d[d$value_type == "observed", ]
      proj <- d[d$value_type == "projected", ]

      if (nrow(obs) > 0) {
        lines(obs$year, obs$mt, col = colour, lwd = 2.4)
        points(obs$year, obs$mt, col = colour, pch = 19, cex = 1.0)
      }
      if (nrow(proj) > 0) {
        bridge <- rbind(obs[nrow(obs), , drop = FALSE], proj)
        lines(bridge$year, bridge$mt, col = colour, lwd = 2.0, lty = 2)
        # Hollow points for projections: a different shape as well as a
        # different line, because line style alone is easy to miss.
        points(proj$year, proj$mt, col = colour, pch = 21, bg = "white",
               cex = 1.0, lwd = 1.8)
      }

      # A partial year is marked on the plot itself, not only in the caption.
      part <- d[!is.na(d$months) & d$months < 12, ]
      if (nrow(part) > 0) {
        text(part$year, part$mt, labels = paste0(part$months, "a"),
             pos = 3, col = "#E8A33D", cex = 0.75, font = 2)
      }
    }

    first <- TRUE
    for (b in c("co2", "co2e_100yr")) {
      if (any(s$gas_basis == b)) {
        draw_one(b, if (b == "co2") "#B2182B" else "#2166AC",
                 if (first) 2 else 4, first)
        first <- FALSE
      }
    }

    abline(v = current_year(), col = "#33333355", lwd = 1.5, lty = 3)
  })

  output$trend_note <- renderUI({
    s <- trend_series()
    if (is.null(s) || nrow(s) == 0) return(NULL)

    tags$p(
      style = "font-size:12px; color:#666; margin:8px 0 0 0;",
      tags$b("İki ayrı eksen, iki ayrı gaz."), " Sol eksen sanayi CO₂, sağ ",
      "eksen enerji CO₂e. Eğriler aynı grafikte ama ",
      tags$b("aynı ölçekte değildir"), " ve toplanmaz. ",
      "Dolu nokta ve düz çizgi gözlem, içi boş nokta ve kesik çizgi kestirimdir. ",
      "Nokta üstündeki turuncu etiket, o yılın kaç aylık veriyle hesaplandığını ",
      "gösterir. Dikey noktalı çizgi slider'ın bulunduğu yıldır."
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

      # The selected year's figures for this facility, with their vintage. Kept
      # in its own block so the time-varying numbers are visibly separate from
      # the attributes that do not change — the same split the data model makes
      # between facilities.rds and facility_panel.rds (§6).
      if (!is.null(panel)) {
        p <- panel |> filter(facility_id == selected_id(), year == current_year())
        if (nrow(p) == 0) {
          tags$p(style = "font-size:12px; color:#888; margin-top:10px;",
                 current_year(), " için panel kaydı yok.")
        } else {
          tags$div(
            style = paste0("margin-top:12px; padding:10px; background:#fafafa;",
                           " border:1px solid #eee;"),
            tags$div(
              style = "font-size:12px; color:#666; margin-bottom:6px;",
              tags$b(current_year()),
              tags$span(class = "yr-badge",
                        style = paste0("margin-left:6px; background:",
                                       if (p$value_type == "projected")
                                         "#7B1FA2" else "#4C9A2A",
                                       "; color:#fff;"),
                        unname(VALUE_TYPE_LABELS[p$value_type])),
              if (!is.na(p$months_covered) && p$months_covered < 12)
                tags$span(style = "margin-left:6px; color:#E8A33D;",
                          paste0(p$months_covered, "/12 ay"))
            ),
            tags$table(
              class = "kv", style = "width:100%;",
              row("Emisyon",
                  paste0(format(round(p$emissions_reported_t / 1000, 1),
                                nsmall = 1),
                         " kt ", GAS_LABELS[[p$gas_basis]])),
              row("Üretim",
                  if (is.na(p$production_activity)) "yayımlanmıyor"
                  else paste0(format(round(p$production_activity),
                                     big.mark = ".", decimal.mark = ","), " ",
                              ifelse(is.na(p$activity_units), "",
                                     p$activity_units))),
              row("Yoğunluk",
                  if (is.na(p$emission_intensity)) "hesaplanamıyor"
                  else format(round(p$emission_intensity, 3), nsmall = 3)),
              row("Güven", ifelse(is.na(p$confidence_emissions), "—",
                                  p$confidence_emissions)),
              row("Sürüm", p$vintage)
            ),
            tags$p(
              style = "font-size:11px; color:#888; margin:8px 0 0 0;",
              tags$b("SKDM maruziyeti hesaplanmıyor."), " Doğrudan/dolaylı ",
              "ayrıştırma yapılmadan bu tesise bir maliyet baskısı rakamı ",
              "atanamaz; boş bırakmak, uydurmaktan iyidir."
            )
          )
        }
      },

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


  output$fleet_summary <- renderUI({
    if (is.null(fleet_renewables)) {
      return(tags$p("Yenilenebilir filo verisi üretilmedi. Çalıştırın: ",
                    tags$code("Rscript scripts/02_build_facilities.R")))
    }

    by_fuel <- fleet_renewables |>
      group_by(fuel_type) |>
      summarise(plants = n(),
                gw = sum(capacity_mw, na.rm = TRUE) / 1000,
                .groups = "drop") |>
      arrange(desc(gw))

    tagList(
      tags$table(
        style = "width:100%; font-size:13px;",
        lapply(seq_len(nrow(by_fuel)), function(i) {
          ft <- by_fuel$fuel_type[i]
          tags$tr(
            tags$td(style = paste0("padding:4px 0; border-left:4px solid ",
                                   FLEET_COLOURS[[ft]], "; padding-left:8px;"),
                    FLEET_LABELS[[ft]]),
            tags$td(style = "text-align:right;", by_fuel$plants[i]),
            tags$td(style = "text-align:right; font-weight:600;",
                    paste0(round(by_fuel$gw[i], 1), " GW"))
          )
        }),
        tags$tr(
          tags$td(style = "padding-top:8px; border-top:1px solid #ddd;",
                  tags$b("Toplam")),
          tags$td(style = "text-align:right; padding-top:8px; border-top:1px solid #ddd;",
                  tags$b(nrow(fleet_renewables))),
          tags$td(style = "text-align:right; padding-top:8px; border-top:1px solid #ddd;",
                  tags$b(paste0(round(sum(by_fuel$gw), 1), " GW")))
        )
      ),
      tags$p(
        style = "margin-top:10px; font-size:12px; color:#666;",
        tags$b("Bu tesisler modellenen 300 kaydın parçası değildir. "),
        "Global Energy Monitor'den gelirler, emisyon üretmezler ve emisyon ",
        "tablolarında yer almazlar. Haritada bulunma sebepleri tek bir soruyu ",
        "cevaplamaktır: Climate TRACE'in elektrik kütüğünün göremediği üretim ",
        "nerede? Kütük ulusal üretimin yaklaşık yarısını görüyor ve görmediği ",
        "yarı, büyük ölçüde burada duruyor."
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
