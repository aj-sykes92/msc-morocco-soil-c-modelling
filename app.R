library(shiny)
library(tidyverse)

# source functions script
source("ipcc-c-model-functions.R")

# define UI for data upload app ----
ui <- fluidPage(
  
  # app title ----
  titlePanel("IPCC (2019) three-pool steady state soil C model"),
  # app subtitle
  h4(HTML("Prepared for MSc EPM & SS Morocco field trip modelling<br/> ")),
  
  
  # sidebar layout
  sidebarLayout(
    
    # sidebar panel
    sidebarPanel(
      
      h4(HTML("Climate data file (defaults to example scenario)<br/> ")),
      
      # select climate data input file
      fileInput(inputId = "clim_data",
                label = "Crop input data file",
                multiple = FALSE,
                accept = c(".rds"),
                placeholder = "morocco-example-climate-data.rds"),
      
      titlePanel(title = "Data input"),
      h4(HTML("Baseline scenario (defaults to example scenario)<br/> ")),
      
      # select crop data file for baseline scenario
      fileInput(inputId = "crop_data_bl",
                label = "Crop input data file",
                multiple = FALSE,
                accept = c("text/csv",
                           "text/comma-separated-values,text/plain",
                           ".csv"),
                placeholder = "morocco-example-crop-data.csv"),
      
      # select manure data file for baseline scenario
      fileInput(inputId = "manure_data_bl",
                label = "Manure input data file",
                multiple = FALSE,
                accept = c("text/csv",
                           "text/comma-separated-values,text/plain",
                           ".csv"),
                placeholder = "morocco-example-manure-data.csv"),
      
      h4(HTML("Modified scenario (defaults to no scenario)<br/> ")),
      
      # select crop data file for modified scenario
      fileInput(inputId = "crop_data_mod",
                label = "Crop input data file",
                multiple = FALSE,
                accept = c("text/csv",
                           "text/comma-separated-values,text/plain",
                           ".csv")),
      
      # select crop data file for modified scenario
      fileInput(inputId = "manure_data_mod",
                label = "Manure input data file",
                multiple = FALSE,
                accept = c("text/csv",
                           "text/comma-separated-values,text/plain",
                           ".csv")),
      
      # run app
      titlePanel(title = "Run model"),
      actionButton(inputId = "run_model",
                   label = "Click to run model"),
      

      h4(HTML(" ")),
      h4(HTML("Export model run as .csv file<br/> ")),
      
      # Output: Download a file ----
      downloadButton(outputId = "download_file",
                     label = "Export .csv",
                     class= "action"),
      
      # CSS style for the download button ----
      tags$style(type='text/css', "#downloadFile { width:100%; margin-top: 35px;}"),
      
    ),
    
    # Main panel for displaying outputs ----
    mainPanel(
      
      h4(HTML("Annual soil carbon stock time series")),
      plotOutput(outputId = "main_plot"),
      
      h4(HTML(" ")),
      h4(HTML("Soil carbon stock change (all values in tonnes / ha)")),
      tableOutput(outputId = "main_table"),
      
      h4(HTML(" ")),
      h4(HTML("Summarised soil carbon stock change per decade")),
      plotOutput(outputId = "second_plot")

    )
  )
)


# Define server logic to read selected file ----
server <- function(input, output) {
  
  options(shiny.maxRequestSize=10*1024^2)
  
  model <- reactiveValues(baseline_data = read_rds("model-scenarios/scenario-baseline.rds"),
                          modified_data = NULL,
                          output_csv = NULL)
  
  # only run baseline model if there's been a change to inputs
  # and assume default inputs if any are undefined
  observeEvent(input$run_model, {
    clim_input <- input$clim_data$datapath
    crop_input <- input$crop_data_bl$datapath
    manure_input <- input$manure_data_bl$datapath
    
    if(!is.null(clim_input) | !is.null(crop_input) | !is.null(manure_input)){
      clim_data <- ifelse(!is.null(clim_input), clim_input, "model-data/morocco-example-climate-data.rds")
      crop_data <- ifelse(!is.null(crop_input), crop_input, "model-data/morocco-example-crop-data.csv")
      manure_data <- ifelse(!is.null(manure_input), manure_input, "model-data/morocco-example-manure-data.csv")
      
      model$baseline_data <- build_model(clim_data = clim_data,
                                         crop_data = crop_data,
                                         manure_data = manure_data)
    }

  })
  
  # only run this one if there's been a change to both outputs, otherwise leave NULL or in previous version
  observeEvent(input$run_model, {
    clim_input <- ifelse(!is.null(input$clim_data$datapath),
                         input$clim_data$datapath,
                         "model-data/morocco-example-climate-data.rds")
    crop_input <- input$crop_data_mod$datapath
    manure_input <- input$manure_data_mod$datapath
    
    if(!is.null(crop_input) & !is.null(manure_input)){
      clim_data <- clim_input
      crop_data <- crop_input
      manure_data <- manure_input
      
      model$modified_data <- build_model(clim_data = clim_input,
                                         crop_data = crop_data,
                                         manure_data = manure_data)
    }
  })
  
  # run csv output generator whenever run button is pressed
  observeEvent(input$run_model, {
    model$output_csv <- build_output(df_bl = model$baseline_data,
                                     df_mod = model$modified_data)
  })
  
  output$main_plot <- renderPlot({
    ts_plot(model$baseline_data, model$modified_data)
  })
  
  output$second_plot <- renderPlot({
    stockchange_plot(model$baseline_data, model$modified_data)
  })

  output$main_table <- renderTable({
    stockchange_table(model$baseline_data, model$modified_data)
  })
  
  # Download handler in Server
  output$download_file <- downloadHandler(
    filename = function() {
      paste0("ipcc-c-model-run-", Sys.Date(), ".csv")
    },
    content = function(con) {
      dataProcessed <- build_output(df_bl = model$baseline_data,
                                    df_mod = model$modified_data)
      write_csv(dataProcessed, con)
    }
  )
  
}

# Create Shiny app ----
shinyApp(ui, server)