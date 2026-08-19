# =============================================================================
# TR Energy Policy Tracker - Module 3: User Interface
# -----------------------------------------------------------------------------
# This file defines the layout only. All reactivity lives in server.R.
# Libraries (shiny, shinydashboard, leaflet, plotly) are loaded by global.R,
# which Shiny sources before this file.
#
# The whole dashboard is driven by ONE state variable: input$year.
# =============================================================================


# --- 1. HEADER ---------------------------------------------------------------
header <- dashboardHeader(
  title = "TR Energy Policy Tracker",
  titleWidth = 300
)


# --- 2. SIDEBAR --------------------------------------------------------------
# The single control surface of the app: the timeline slider.
sidebar <- dashboardSidebar(
  width = 300,

  # Contextual heading for the control below.
  tags$div(
    style = "padding: 15px 15px 0 15px; color: #b8c7ce;",
    tags$h4("Timeline", style = "margin-top: 0; font-weight: 600;"),
    tags$p(
      "Move the slider to filter power plants by commissioning year and to ",
      "load the policy landscape of that year.",
      style = "font-size: 12px; line-height: 1.4;"
    )
  ),

  # THE master state variable. Everything downstream reacts to this.
  #  - sep = "" prevents the label rendering as "2,026"
  #  - animate lets the user "play" Turkey's energy build-out over time
  sliderInput(
    inputId = "year",
    label   = "Select Year:",
    min     = 2000,
    max     = 2026,
    value   = 2026,      # default: present day / full dataset
    step    = 1,
    sep     = "",
    ticks   = FALSE,
    width   = "90%",
    animate = animationOptions(interval = 900, loop = FALSE)
  ),

  # Small legend so the map colours are interpretable without a click.
  tags$div(
    style = "padding: 10px 15px; color: #b8c7ce; font-size: 12px;",
    tags$hr(style = "border-color: #4b5c66;"),
    tags$p("Map shows all plants commissioned on or before the selected year.")
  )
)


# --- 3. BODY -----------------------------------------------------------------
body <- dashboardBody(

  # Minor styling: keep box headers readable and give the map a clean frame.
  tags$head(
    tags$style(HTML("
      .content-wrapper { background-color: #f4f6f9; }
      .box { border-top-width: 3px; }
      .policy-scroll { max-height: 260px; overflow-y: auto; }
    "))
  ),

  fluidRow(

    # -- LEFT COLUMN (8/12): the interactive map --------------------------
    column(
      width = 8,

      box(
        # width = NULL makes the box fill its parent column.
        width       = NULL,
        title       = textOutput("map_title", inline = TRUE),
        status      = "primary",
        solidHeader = TRUE,
        # Spinner-free simple output; server renders the leaflet proxy on year change.
        leafletOutput(outputId = "map", height = 620)
      )
    ),

    # -- RIGHT COLUMN (4/12): policy text + emissions chart ----------------
    column(
      width = 4,

      # 3a. Domestic policy insight panel for the selected year.
      box(
        width       = NULL,
        title       = "Domestic Policy Insights",
        status      = "warning",
        solidHeader = TRUE,
        collapsible = TRUE,
        tags$div(
          class = "policy-scroll",
          # Rendered server-side (renderUI) so we can emit formatted HTML
          # from policies/domestic_policy.json rather than a flat string.
          uiOutput(outputId = "policy_panel")
        )
      ),

      # 3b. NDC target vs. actual GHG emissions, with a marker on input$year.
      box(
        width       = NULL,
        title       = "Emissions: Target vs. Actual",
        status      = "danger",
        solidHeader = TRUE,
        collapsible = TRUE,
        plotlyOutput(outputId = "emissions_chart", height = 300)
      )
    )
  )
)


# --- 4. ASSEMBLE -------------------------------------------------------------
# The final expression in ui.R is what Shiny uses as the UI object.
dashboardPage(
  skin   = "blue",
  header = header,
  sidebar = sidebar,
  body   = body
)
