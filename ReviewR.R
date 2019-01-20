# ReviewR: A light-weight, portable tool for reviewing individual patient records
#
# https://zenodo.org/badge/latestdoi/140004344
#
# This is a shiny tool that allows for manual review of the MIMIC-III (https://mimic.physionet.org/) or 
# OMOP (https://www.ohdsi.org/data-standardization/the-common-data-model/) database.  Current support is
# for Postgres and Google BigQuery, with more to come in the future. 
#
# This is a work in progress and thus there are no guarantees of functionality or accuracy. Use at your own risk.


source('lib/reviewr-core.R')

# We will make sure all required packages are installed and loaded
check.packages(c("shiny", "shinyjs", "shinydashboard", "shinycssloaders",
                 "tidyverse", "DT", "dbplyr", "magrittr", "readr"))

## CONFIGURATION
# Here is where you specify your configuration settings for ReviewR.  Please see Configuration.md for more information.
app_config <- list(data_model="OMOP",
                   db_engine="postgres",
                   database="ohdsi",
                   host="localhost",
                   port=5432,
                   user="ohdsi",
                   password="ohdsi",
                   schema="public")

# app_config <- list(data_model="OMOP",
#                    db_engine="bigquery",
#                    project_id="class-coursera-dev",
#                    dataset="synpuf1k_omop_cdm")

# Define server logic 
server <- function(input, output, session) {
  options("httr_oob_default" = TRUE)

  output$title = renderText({ paste0("ReviewR (", app_config$data_model, ")") })
  output$data_model = renderText({app_config$data_model})
  
  connection <- NULL
  tryCatch({
    # Initialize the ReviewR application
    connection <- initialize(app_config)
  },
  error=function(e) {
    showNotification(
      paste("There was an error when trying to connect to the database.  Please make sure that you have configured the application correctly, and that the database is running and accessible from your machine.\r\n\r\n",
            "You will need to resolve the connection issue before ReviewR will work properly.  If you need help configuring ReviewR, please see the README.md file that is packaged with the repository.\r\n\r\nError:\r\n", e),
      duration = NULL, type = "error", closeButton = FALSE)
  },
  warning=function(w) {})
  
  if (tolower(app_config$data_model) == "mimic") {
    render_data_tables = mimic_render_data_tables
  }
  else if (tolower(app_config$data_model) == "omop") {
    render_data_tables = omop_render_data_tables
  }
  else {
    stop("Currently this application only supports MIMIC III and OMOP data models")
  }
  
  has_projects = FALSE
  output$has_projects <- reactive({ has_projects })

  output = render_data_tables(input, output, connection)
  output$navigate_links <- renderUI({fluidRow(class="home_container",
                                              column(8,
                                                     div(class="jumbotron home_panel",
                                                         h3("Browse Patients"),
                                                         div(paste0("Navigate through the full list of patients"), class="lead"),
                                                         actionLink(inputId = "viewPatients", label = "View Patients", class="btn btn-primary btn-lg")))
  )}) #renderUI

  output$subject_id_output <- renderText({paste("Subject ID - ",input$subject_id)})
  output$subject_id <- renderText({input$subject_id})
  
  patient_nav_previous = tags$div(actionButton("prev_patient",HTML('
<div class="col-sm-4"><i class="fa fa-angle-double-left"></i> Previous</div>
')))
  patient_nav_next = div(actionButton("next_patient",HTML('
<div class="col-sm-4">Next <i class="fa fa-angle-double-right"></i></div>
')))
  output$patient_navigation_list=renderUI({
    div(column(1,offset=0,patient_nav_previous),column(1,offset=9,patient_nav_next))
  })
  
  # Because we want to use uiOutput for the patient chart panel in multiple locations in the UI,
  # we need to implement the workaround described here (https://github.com/rstudio/shiny/issues/743)
  # where we actually render multiple outputs for each use.
  patient_chart_panel = reactive({
    table_names <- get_review_table_names(app_config$data_model)
    tabs <- lapply(table_names, function(id) { create_data_panel(id, paste0(id, "_tbl"))})
    panel <- div(
      fluidRow(column(12, h2(textOutput("subject_id_output")))),
      br(),
      fluidRow(column(12, do.call(tabsetPanel, tabs)))
    ) #div
    panel
  })
  output$patient_chart_panel_abstraction <- renderUI({ patient_chart_panel() })
  output$patient_chart_panel_no_abstraction <- renderUI( {patient_chart_panel() })
  
  output$selected_project_title <- renderText({
    ifelse(is.null(input$project_id),
           "(No project selected)",
           paste("Project: ", project_list[project_list$id == input$project_id, "name"]))
  })
  output$selected_project_id <- renderText({input$project_id})
  
  session$onSessionEnded(function() {
    if (!is.null(connection) & !is.null(connection$dbi_conn)) {
      dbDisconnect(connection$dbi_conn)
    }
  })
  
  observeEvent(input$viewProjects, {
    updateTabsetPanel(session = session, inputId = "tabs", selected = "projects")
  })
  observeEvent(input$viewPatients, {
    updateTabsetPanel(session = session, inputId = "tabs", selected = "patient_search")
  })
  
  outputOptions(output, "has_projects", suspendWhenHidden = FALSE)
}


# Define UI for application 
ui <- dashboardPage(
  dashboardHeader(title = textOutput('title')),
  dashboardSidebar(
    sidebarMenu(
      id = "tabs",
      menuItem("Home", tabName = "home", icon = icon("home")),
      menuItem("Patient Search", tabName = "patient_search", icon = icon("users")),
      menuItem("Chart Review", icon = icon("table"), tabName = "chart_review")
    )
  ),
  dashboardBody(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "app.css")),
    
    tabItems(
      tabItem(tabName = "home",
              h2("Welcome to ReviewR"),
              htmlOutput("navigate_links")
      ), #tabItem
      tabItem(tabName = "projects",
              conditionalPanel(
                condition = "!(input.project_id)",
                h2("Select a project to work on"),
                withSpinner(DT::dataTableOutput('projects_tbl'))
              ),
              conditionalPanel(
                condition = "(input.project_id)",
                h2(textOutput("selected_project_title")),
                HTML("<a id='reset_project_id' href='#' onclick='Shiny.onInputChange(\"project_id\", null);'>View All Projects</a>"),
                div(id="active_cohort",
                    withSpinner(DT::dataTableOutput('cohort_tbl')))
              )
      ),
      tabItem(tabName = "patient_search",
              h2("Select a patient to view"),
              withSpinner(DT::dataTableOutput('all_patients_tbl'))
      ),
      tabItem(tabName = "chart_review",
              conditionalPanel(
                condition = "input.subject_id == null || input.subject_id == undefined || input.subject_id == ''",
                h4("Please select a patient from the 'Patient Search' tab")
              ),
              conditionalPanel(
                condition = "input.subject_id != ''",
                uiOutput("patient_navigation_list"),
                uiOutput("patient_chart_panel_no_abstraction")
              ) #conditionalPanel
      ) #tabItem
    )
  )
)


# Run the application 
shinyApp(ui = ui, server = server)
