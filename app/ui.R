# =============================================================================
# ui.R — interface definition
# -----------------------------------------------------------------------------
# Turkish labels throughout; English code and identifiers (KARBON_ATLASI.md §2).
#
# SCOPE: both populations on one map — 88 industrial installations and 212
# energy assets. No time slider yet: `facility_panel.rds` does not exist, so a
# slider would have nothing to move. It takes the prominent sidebar position
# once the panel is built.
# =============================================================================

dashboardPage(
  skin = "black",

  # --- HEADER ---------------------------------------------------------------
  dashboardHeader(
    title = "Türkiye Karbon Atlası",
    titleWidth = 300
  ),

  # --- SIDEBAR --------------------------------------------------------------
  dashboardSidebar(
    width = 300,

    sidebarMenu(
      id = "tab",
      menuItem("Tesis Haritası",  tabName = "map",     icon = icon("map-location-dot")),
      menuItem("Şebeke Yoğunluğu", tabName = "grid",    icon = icon("bolt")),
      menuItem("Veri Kaynakları",  tabName = "sources", icon = icon("book"))
    ),

    tags$hr(style = "border-color: #4b5c66; margin: 10px 15px;"),

    tags$div(
      style = "padding: 0 15px;",

      # asset_class is the first thing every filter, colour and aggregate keys
      # on (§6), so it is the first control the user meets.
      checkboxGroupInput(
        inputId  = "asset_classes",
        label    = "Varlık sınıfı",
        choices  = setNames(names(ASSET_CLASS_LABELS), unname(ASSET_CLASS_LABELS)),
        selected = names(ASSET_CLASS_LABELS)
      ),

      selectizeInput(
        inputId  = "sectors",
        label    = "Sektör",
        choices  = SECTOR_CHOICES_BY_CLASS,
        selected = ALL_SECTORS,
        multiple = TRUE,
        options  = list(placeholder = "Tüm sektörler")
      ),

      selectizeInput(
        inputId  = "provinces",
        label    = "İl",
        choices  = PROVINCE_CHOICES,
        selected = NULL,
        multiple = TRUE,
        options  = list(placeholder = "Tüm iller")
      ),

      tags$hr(style = "border-color: #4b5c66;"),

      checkboxInput(
        inputId = "flag_uncertain",
        label   = "Konum ataması belirsiz olanları vurgula",
        value   = FALSE
      ),

      checkboxInput(
        inputId = "only_captive",
        label   = "Yalnızca kendi tesisini besleyen santraller",
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
        .small-box h3 { font-size: 26px; }
        .estimate-note {
          background: #FFF8E1; border-left: 4px solid #E8A33D;
          padding: 10px 14px; margin-bottom: 12px; font-size: 13px;
        }
        .basis-note {
          background: #EAF2FA; border-left: 4px solid #2166AC;
          padding: 10px 14px; margin-bottom: 12px; font-size: 13px;
        }
        .leaflet-container { background: #f4f6f9; }
        table.kv td { padding: 4px 10px 4px 0; font-size: 13px; }
      "))
    ),

    tabItems(

      # ---- TAB: MAP --------------------------------------------------------
      tabItem(
        tabName = "map",

        # Every emissions figure in this project is a modelled estimate, and the
        # interface has to say so where the user can see it, not in a footnote
        # (§8.3).
        tags$div(
          class = "estimate-note",
          tags$strong("Bu veriler modellenmiş tahmindir."),
          " Tesis düzeyinde doğrulanmış sera gazı raporları Türkiye'de kamuya",
          " açık değildir. Konumlar ve tesis bilgileri Climate TRACE",
          " kestirimlerine dayanır ve ölçüm değildir."
        ),

        # The single most misreadable thing on this page is a total spanning
        # both populations, so the interface refuses the idea before it forms.
        tags$div(
          class = "basis-note",
          tags$strong("İki popülasyon, iki gaz tabanı."),
          " Sanayi tesisleri CO₂ cinsinden (SKDM bir CO₂ aracıdır); enerji",
          " varlıkları CO₂e cinsinden, çünkü kömür ocaklarının ayak izinin",
          " yalnızca %18'i CO₂'dir. ",
          tags$b("Bu iki taban toplanmaz.")
        ),

        fluidRow(
          valueBoxOutput("box_total",      width = 3),
          valueBoxOutput("box_industrial", width = 3),
          valueBoxOutput("box_energy",     width = 3),
          valueBoxOutput("box_year",       width = 3)
        ),

        fluidRow(
          column(
            width = 8,
            box(
              width = NULL, status = "primary", solidHeader = TRUE,
              title = textOutput("map_title", inline = TRUE),
              leafletOutput("map", height = 620)
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
              collapsible = TRUE, collapsed = TRUE,
              uiOutput("geocode_summary")
            ),
            box(
              width = NULL, status = "success", solidHeader = TRUE,
              title = "Devreye Giriş Yılı Kapsaması",
              collapsible = TRUE, collapsed = TRUE,
              uiOutput("commissioning_summary")
            )
          )
        )
      ),

      # ---- TAB: GRID INTENSITY ---------------------------------------------
      # The disagreement between estimates is itself a result (§7), so it gets a
      # tab rather than a footnote.
      tabItem(
        tabName = "grid",
        fluidRow(
          box(
            width = 12, status = "primary", solidHeader = TRUE,
            title = "Şebeke Karbon Yoğunluğu — Üç Bağımsız Tahmin",
            uiOutput("grid_panel")
          )
        )
      ),

      # ---- TAB: SOURCES ----------------------------------------------------
      # Climate TRACE, GEM and Ember are all CC BY 4.0 — attribution is a
      # licence condition, so this tab is required, not decorative (§10).
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
