
repo = "http://cran.us.r-project.org"
library(caret)
library(ggfortify)
library(ggplot2)
library(dplyr)
library(RSQLite)
library(DBI)
library(class)
library(MASS)
# library(pscl)
library(nnet)
library(randomForest)
library(e1071)

run_model = function(model_type, trn_data, trn_in_data, trn_out_data, tst_in_data, tst_out_data, fmla){
  if (model_type != 'rf' & model_type != 'zeroinf'){
  #if (1==0){
  print('normalizing')
	train_col_stds = apply(trn_in_data, 2, sd)
	train_col_means = colMeans(trn_in_data)

	train_normalized = t((t(trn_in_data)-train_col_means)/train_col_stds)
	test_normalized = t((t(tst_in_data)-train_col_means)/train_col_stds)

	pca = prcomp(train_normalized)

	trn_preprocessed = predict(pca, train_normalized)
	tst_preprocessed = predict(pca, test_normalized)

	fmla = as.formula(paste(out_col_name, "~", paste(colnames(trn_preprocessed), collapse="+")))

	train_data = cbind(as.data.frame(trn_preprocessed), num_flooded = model_data[prt$Resample1, out_col_name])
	train_in_data = trn_preprocessed
	test_in_data = tst_preprocessed
  	if (model_type == 'poisson'){output = glm(fmla, data=train_data, family = poisson)}
  	else if (model_type == 'quasipoisson'){output = glm(fmla, data=train_data, family = quasipoisson)}
	  else if (model_type == 'negb'){output = glm.nb(fmla, data=train_data)}
	  else if (model_type == 'ann'){
	    num_units_in_hidden_layers = 10 # called M in our notes and text
	    range_for_initial_random_weights = 0.7 # see next three lines of comments
	    weight_decay = 5e-1 # weight decaay to avoid overfitting
	    maximum_iterations = 400 # maximum number of iterations in training
	    output = nnet(fmla, data=train_data, 
	                  size = num_units_in_hidden_layers, 
	                  rang = range_for_initial_random_weights,
	                  decay = weight_decay, 
	                  maxit = maximum_iterations)
	    }
	  else if (model_type == 'svm'){output = svm(fmla, data=train_data)}
	
  }
  else if (model_type == 'rf'){
	output = randomForest(fmla, data=trn_data, importance = TRUE)
	impo = as.data.frame(output$importance)
	impo = impo[,1]
  }
  #else if (model_type == 'poisson'){output = glm(fmla, data=trn_data, family = poisson)}
  #else if (model_type == 'zeroinf'){
	#output = zeroinfl(fmla, data=trn_data, importance = TRUE)
  #}
  #else if (model_type == 'quasipoisson'){output = glm(fmla, data=trn_data, family = quasipoisson)}
  #else if (model_type == 'negb'){output = glm.nb(fmla, data=trn_data)}
  #else if (model_type == 'ann'){
    #num_units_in_hidden_layers = 3 # called M in our notes and text
    #range_for_initial_random_weights = 0.5 # see next three lines of comments
    #weight_decay = 5e-4 # weight decaay to avoid overfitting
    #maximum_iterations = 400 # maximum number of iterations in training
    #output = nnet(fmla, data=train_data, 
                  #size = num_units_in_hidden_layers, 
                  #rang = range_for_initial_random_weights,
                  #decay = weight_decay, 
                  #maxit = maximum_iterations)
  #}
  #else if (model_type == 'svm'){output = svm(fmla, data=train_data)}
  
  pred_trn = predict(output, newdata = as.data.frame(train_in_data), type='response')

  pred_tst = predict(output, newdata = as.data.frame(test_in_data), type='response')
  #pred_capped = replace(pred, pred > 159, 159)
  if (model_type == 'rf'){
       return(list(pred_trn, pred_tst, impo))
  }
  else {
       return(list(pred_trn, pred_tst))
  }
  
}

remove_cols= function(l, cols){
    return(l[! l %in% cols])
}

base_dir<- "C:/Users/Jeff/Documents/research/Sadler_3rdPaper/manuscript/"
data_dir<- "C:/Users/Jeff/Google Drive/research/Sadler_3rdPaper_Data/"
fig_dir <- paste(base_dir, "Figures/general/", sep="")
db_filename <- "floodData.sqlite"

con = dbConnect(RSQLite::SQLite(), dbname=paste(data_dir, db_filename, sep=""))

df = dbReadTable(con, 'for_model_avgs')

colnames(df)

set.seed(5)


cols_to_remove = c('event_name', 'event_date', 'num_flooded')
in_col_names = remove_cols(colnames(df), cols_to_remove)
out_col_name = 'num_flooded'

model_data = df[, append(in_col_names, out_col_name)]
model_data = na.omit(model_data)
model_data = model_data[model_data[,'rd']>0.01,]
import_df = data.frame(matrix(nrow=17))
all_pred_tst = c()
all_pred_trn = c()
all_tst = c()
all_trn = c()
fomla = as.formula(paste(out_col_name, "~", paste(in_col_names, collapse="+")))
model_types = c('poisson', 'rf')
suffix = 'revisions1'
#dbGetQuery(con, paste("DROP TABLE ", 'rf', '_', suffix, '_trn', sep=""))
#dbGetQuery(con, paste("DROP TABLE ", 'poisson', '_', suffix, '_trn', sep=""))
#dbGetQuery(con, paste("DROP TABLE ", 'rf', '_', suffix, '_tst', sep=""))
#dbGetQuery(con, paste("DROP TABLE ", 'poisson', '_', suffix, '_tst', sep=""))
#dbGetQuery(con, paste('rf_impo_', suffix, sep=""))
for (i in 1:100){
  prt = createDataPartition(model_data[, out_col_name], p=0.7)
  train_data = model_data[prt$Resample1,]
  train_in_data = train_data[, in_col_names]
  train_out_data = train_data[, out_col_name]
  test_in_data = model_data[-prt$Resample1, in_col_names]
  test_out_data = model_data[-prt$Resample1, out_col_name]
  
  for (model in model_types){
	  print(paste("run: ", i, sep = ''))

    model_results = run_model(model, train_data, train_in_data, train_out_data, test_in_data, test_out_data, fomla)
	  pred_train = model_results[1]
	  pred_test = model_results[2]

	 # all_trn = append(all_trn, train_out_data)
	  #all_tst = append(all_tst, test_out_data)
	  #all_pred_trn = append(all_pred_trn, unlist(pred_train))
	  #all_pred_tst = append(all_pred_tst, unlist(pred_test))
	  all_trn_df = data.frame(train_out_data, unlist(pred_train))
	  all_tst_df = data.frame(test_out_data, unlist(pred_test))
	  dbWriteTable(con, paste(model, '_', suffix, '_trn', sep=""), all_trn_df, append=TRUE)
	  dbWriteTable(con, paste(model, '_', suffix, '_tst', sep=""), all_tst_df, append=TRUE)

	  if (model == 'rf'){
      impo = model_results[3]
	    import_df = cbind(import_df, impo)
	  }
	}
}
colnames(import_df) = 1:ncol(import_df)
row.names(import_df) = in_col_names
dbWriteTable(con, paste('rf_impo_', suffix, sep=""), import_df, overwrite=TRUE)
