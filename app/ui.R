# =============================================================================
# ui.R — interface definition
# -----------------------------------------------------------------------------
# Turkish labels throughout; English code and identifiers (SKDM_TURKIYE.md §2).
#
# This file replaces an earlier ui.R written against a superseded brief (an
# energy-policy tracker with English labels). §11 required a rewrite rather than
# an extension; the old version remains in git history.
#
# SCOPE: facility map only. No time slider yet — facility_panel.rds does not
# exist, so a slider would have nothing to move. It is added when the panel is.
# =============================================================================

dashboardPage(
  skin = "black",

  # --- HEADER ---------------------------------------------------------------
  dashboardHeader(
    title = "SKDM Türkiye",
    titleWidth = 300
  ),

  # --- SIDEBAR --------------------------------------------------------------
  dashboardSidebar(
    width = 300,

    sidebarMenu(
      id = "tab",
      menuItem("Tesis Haritası", tabName = "map",     icon = icon("map-location-dot")),
      menuItem("Veri Kaynakları", tabName = "sources", icon = icon("book"))
    ),

    tags$hr(style = "border-color: #4b5c66; margin: 10px 15px;"),

    # Filters. These are the only controls in this version; the time slider
    # takes the prominent position here once the panel exists.
    tags$div(
      style = "padding: 0 15px;",

      checkboxGroupInput(
        inputId  = "sectors",
        label    = "Sektör",
        choices  = SECTOR_CHOICES,
        selected = names(SECTOR_LABELS)
      ),

      selectizeInput(
        inputId  = "provinces",
        label    = "İl",
        choices  = PROVINCE_CHOICES,
        selected = NULL,
        multiple = TRUE,
        options  = list(placeholder = "Tüm iller")
      ),

      checkboxInput(
        inputId = "flag_uncertain",
        label   = "Konum ataması belirsiz olanları vurgula",
        value   = FALSE
      )
    )
  ),

  # --- BODY -----------------------------------------------------------------
  dashboardBody(

    # charset must be declared explicitly or Turkish characters can render as
    # mojibake regardless of the file's own encoding (§2).
    tags$head(
      tags$meta(charset = "UTF-8"),
      tags$style(HTML("
        .content-wrapper { background-color: #f4f6f9; }
        .small-box h3 { font-size: 28px; }
        .estimate-note {
          background: #FFF8E1; border-left: 4px solid #E8A33D;
          padding: 10px 14px; margin-bottom: 12px; font-size: 13px;
        }
        .leaflet-container { background: #f4f6f9; }
      "))
    ),

    tabItems(

      # ---- TAB: MAP --------------------------------------------------------
      tabItem(
        tabName = "map",

        # Every emissions figure in this project is a modelled estimate, and the
        # interface has to say so where the user can see it, not in a footnote
        # (§8.3). It appears above the map deliberately.
        tags$div(
          class = "estimate-note",
          tags$strong("Bu veriler modellenmiş tahmindir."),
          " Tesis düzeyinde doğrulanmış sera gazı raporları Türkiye'de kamuya",
          " açık değildir. Konumlar ve tesis bilgileri Climate TRACE",
          " kestirimlerine dayanır ve ölçüm değildir."
        ),

        fluidRow(
          valueBoxOutput("box_total",    width = 3),
          valueBoxOutput("box_steel",    width = 3),
          valueBoxOutput("box_cement",   width = 3),
          valueBoxOutput("box_aluminum", width = 3)
        ),

        fluidRow(
          column(
            width = 8,
            box(
              width = NULL, status = "primary", solidHeader = TRUE,
              title = textOutput("map_title", inline = TRUE),
              leafletOutput("map", height = 600)
            )
          ),
          column(
            width = 4,
            box(
              width = NULL, status = "warning", solidHeader = TRUE,
              title = "Seçili Tesis",
              uiOutput("facility_detail")
            ),
            box(
              width = NULL, status = "info", solidHeader = TRUE,
              title = "Konum Ataması Güvenilirliği",
              collapsible = TRUE,
              uiOutput("geocode_summary")
            )
          )
        )
      ),

      # ---- TAB: SOURCES ----------------------------------------------------
      # Climate TRACE is CC BY 4.0 — attribution is a licence condition, so this
      # tab is required, not decorative (§8.6).
      tabItem(
        tabName = "sources",
        fluidRow(
          box(
            width = 12, status = "primary", solidHeader = TRUE,
            title = "Veri Kaynakları ve Atıf",
            uiOutput("sources_panel")
          )
        )
      )
    )
  )
)
