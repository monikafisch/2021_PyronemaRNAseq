############################
### Install sleuth et al ###
############################
# generally follow these instructions: https://pachterlab.github.io/sleuth/download.html
# for bioconductor packages, it's best to follow the instructions on bioconductor.org"
if (!requireNamespace("BiocManager", quietly = TRUE))
  install.packages("BiocManager")
BiocManager::install("rhdf5")

install.packages("devtools")
devtools::install_github("pachterlab/sleuth")
library("sleuth")

## Note: the input file for sleuth is a particular file output from kallisto! 
## Must use kallisto prior to sleuth!!
## input file for DESeq2 is a raw counts table!

############################
########## DESeq2! #########
############################

if (!requireNamespace("BiocManager", quietly = TRUE))
  install.packages("BiocManager")

BiocManager::install("DESeq2")


library(data.table)
library(DESeq2)
library(geneplotter)
library(pheatmap)
library(RColorBrewer)
library(ggplot2)
library(dplyr)

# Note that DESeq2 will calculate a single statistic and p-value for 
# [reference condition] vs. [all other provided samples]
# So if you have more than two conditions they need to be broken up into
# seperate directories for DESeq2. But, it's useful as an initial overview 
# of your data to consider all samples all together.
# Below, Step 1 is the initial overview of all the data together
# Step 2 is teasing apart [condition X] vs. [reference condition]
# and calculating DE for all pairwise combos of conditions.

###############################################
#### STEP 1: LOOK AT ALL THE DATA TOGETHER ####
## PCA PLOT & SAMPLE-SAMPLE DISTANCE HEATMAP ##
###############################################

# Specify the directory where my HTSeq raw counts files are located:
directory <- "~/RawCounts_HTSeq0.9.1/all"

# Create a list of all the files in the directory that begin with "MF"
# (all sample file have a format like this: "FSC1rawcounts.txt")
sampleFiles <- grep("FS", list.files(directory), value=TRUE)
sampleFiles

# Make a list of the conditions, or strains:
sampleCondition <- c("char", "char", "char", 
                     "ICB", "ICB", "ICB",
                     "sucrose", "sucrose", "sucrose",
                     "water","water","water")
                     

# Compile the file and condition lists into a table that DESeq can use:
sampleTable <- data.frame(sampleName=sampleFiles, 
                          fileName=sampleFiles, 
                          condition=sampleCondition)

# Look at sampleTable, make sure the values in the sampleCondition column 
# matches up correctly with the sampleFiles collumn. Might need to go back
# and change the order that you list conditions in for sampleCondition...
sampleTable

# Create the DESeq Dataset from HTseq counts:
# Note that this function is specific for connecting DESeq2 and HTSeq!
ddsHTSeq <- DESeqDataSetFromHTSeqCount(sampleTable=sampleTable, 
                                       directory=directory, 
                                       design=~condition)

# Remove genes with a raw count of 1 or 0:
dds.filtered <- ddsHTSeq[rowSums(counts(ddsHTSeq)) > 1, ]

# Indicate the reference condition for calculating differential expression
dds.filtered$condition <- relevel(dds.filtered$condition, ref="sucrose")

# Run DESeq2!
dds.DESeq <- DESeq(dds.filtered)

# Use the assay function to view a DESeq2 object:
head(assay(dds.DESeq))
dds.DESeq$condition

############################################
# David's Favorite quality control heatmap #
############################################
# Sample-to-sample Distance Plot #
# Extract the matrix of normalized values:
rld <- rlog(dds.DESeq) #regular log2 transformation
sampleDists <- dist(t(assay(rld))) #calculate sample-to-sample Euclidean distances
sampleDistMatrix <- as.matrix(sampleDists) #convert to a matrix
rownames(sampleDistMatrix) <- paste(rld$condition, rld$type)
colnames(sampleDistMatrix) <- paste(rld$condition, rld$type)
colors <- colorRampPalette( rev(brewer.pal(9, "YlGnBu")) )(255)
pheatmap(sampleDistMatrix,
         clustering_distance_rows=sampleDists,
         clustering_distance_cols=sampleDists,
         col=colors)
# Color code key: http://www.datavis.ca/sasmac/brewer.all.jpg
# heatmap shows Euclidean distance between samples

citation("vegan")
#PERMANOVA to test for a statistically significant differences between treatments:
adonis(sampleDists ~ dds.DESeq$condition) 
# p-value = 0.001!
# note that distances are Euclidean and should be the same for both plotPCA() below, and the pheatmap() above

###############################################
# PCA plot to visualize how the data clusters #
###############################################
rld <- rlog(dds.DESeq) #regular log2 transformation of DEseq object
#prcomp() PCA that works with DEseq2 objects:
plotPCA(rld, intgroup=c("condition")) 
#Export PCA results to a data.frame that can be read into ggplot2:
data <- plotPCA(rld, intgroup=c("condition"), returnData=TRUE)
percentVar <- round(100 * attr(data, "percentVar"))
ggplot(data, aes(PC1, PC2, color=condition)) +
  geom_point(size=3) +
  xlab(paste0("PC1: ",percentVar[1],"% variance")) +
  ylab(paste0("PC2: ",percentVar[2],"% variance"))+
  scale_color_manual(values = c("#0075d6", "black", "#d66100", "#75d600")) +
  scale_fill_manual(values = c("#0075d6", "black", "#d66100", "#75d600")) +
  theme(plot.background = element_rect(fill="white"),
        panel.background = element_rect(fill="white"),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_blank(),
        panel.border = element_rect(fill = NA, colour = "black", size = 0.3), 
        legend.background = element_rect(fill = "white"),
        legend.text = element_text(size=14, face="bold", color="black"),
        legend.title = element_text(size=16, face="bold", color="black"),  
        legend.key = element_rect(color = "white",  fill = "white"),  
        axis.ticks = element_line(color="black"),
        axis.text = element_text(size = 12),
        axis.title = element_text(size=20, face="bold", color="black"),
        axis.text.x = element_text(size=14, face="bold", hjust=0.5, vjust=1, angle=0, color="black"),
        axis.text.y = element_text(size=14, face="bold", color="black"))

# Plot PCA with 95% CI circles around the dots!
#duplicate data so that each point on the PCA is actually 2 points
#...because the stat_ellipse() function requires a minimum of 4 points/condition!
data2 <- copy(data)#remove this line if you dont want to use stat_ellipse()
data2$PC1 <- data2$PC1 + 3
data2$PC2 <- data2$PC2 + 5
data3 <- rbind(data, data2) #remove this line if you dont want to use stat_ellipse()
percentVar <- round(100 * attr(data3, "percentVar"))
ggplot(data3, aes(PC1, PC2, color=condition)) +
  geom_point(size=1.5) +
  xlab(paste0("PC1: ",percentVar[1],"% variance")) +
  ylab(paste0("PC2: ",percentVar[2],"% variance"))+
  scale_color_manual(values = c("#0075d6", "black", "#d66100", "#75d600")) +
  scale_fill_manual(values = c("#0075d6", "black", "#d66100", "#75d600")) +
  #stat_ellipse(geom="polygon", aes(fill=condition), alpha=0.2)+ #remove this line if you dont want to use stat_ellipse()
  #geom_polygon(aes(fill=condition), alpha=0.2) +
  #geom_density2d(alpha=0.5)+
  geom_mark_hull(concavity = 5, expand=0, radius=0, aes(fill=condition))+
  theme(plot.background = element_rect(fill="white"),
        panel.background = element_rect(fill="white"),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_blank(),
        panel.border = element_rect(fill = NA, colour = "black", size = 0.3), 
        legend.background = element_rect(fill = "white"),
        legend.text = element_text(size=14, face="bold", color="black"),
        legend.title = element_text(size=16, face="bold", color="black"),  
        legend.key = element_rect(color = "white",  fill = "white"),  
        axis.ticks = element_line(color="black"),
        axis.text = element_text(size = 12),
        axis.title = element_text(size=20, face="bold", color="black"),
        axis.text.x = element_text(size=14, face="bold", hjust=0.5, vjust=1, angle=0, color="black"),
        axis.text.y = element_text(size=14, face="bold", color="black"))


#
##
#
###############################################
#### STEP 2: ANALYZE DE BETWEEN CONDITIONS #### 
###############################################
# load annotation table from Igor to connect geneID's with their annotations/predicted-function
annotdat <- fread("~RNAseq/Pyrdom1_gff_proteinID_annotation.csv")
names(annotdat)[1] <- "geneID" #rename first column to something more meaningful

# Specify the directory where my HTSeq raw counts files are located:
directory <- "~/RawCounts_HTSeq0.9.1/WvC"
directory <- "~RawCounts_HTSeq0.9.1/WvV"
directory <- "~/RawCounts_HTSeq0.9.1/WvI"
directory <- "~/RawCounts_HTSeq0.9.1/VvC"
directory <- "~/RawCounts_HTSeq0.9.1/VvI"
directory <- "~/RawCounts_HTSeq0.9.1/CvI"

# Create a list of all the files in the directory that begin with "MF"
# (all sample file have a format like this: "FSC1rawcounts.txt")
sampleFiles <- grep("FS", list.files(directory), value
                    =TRUE)
sampleFiles

# Make a list of the conditions, or strains:
sampleCondition <- c("sucrose","sucrose","sucrose", "water", "water", "water")

# Compile the file and condition lists into a table that DESeq can use:
sampleTable <- data.frame(sampleName=sampleFiles, 
                          fileName=sampleFiles, 
                          condition=sampleCondition)

# Look at sampleTable, make sure the values in the sampleCondition column 
# matches up correctly with the sampleFiles collumn. Might need to go back
# and change the order that you list conditions in for sampleCondition...
sampleTable

# Create the DESeq Dataset from HTseq counts:
# Note that this function is specific for connecting DESeq2 and HTSeq!
ddsHTSeq <- DESeqDataSetFromHTSeqCount(sampleTable=sampleTable, 
                                       directory=directory, 
                                       design=~condition)

# Remove genes that have a raw count of 1 or 0 in all samples:
dds.filtered <- ddsHTSeq[rowSums(counts(ddsHTSeq)) > 1, ]

# Indicate the reference condition for calculating differential expression
dds.filtered$condition <- relevel(dds.filtered$condition, ref="sucrose")

# Run DESeq2!
dds.DESeq <- DESeq(dds.filtered)

# Use the assay function to view a DESeq2 object:
#head(assay(dds.DESeq))

# Calculate normalized mean for each strain:
# DESeq2 default is to calculate a single mean across all strains and conditions
# This will give you the average expression of all reps for each condition
# DESeq2 count normalization method is called "median of ratios", analogous to TPM or FPKM
# "Median of ratio" normalization accounts for read depth and RNA composition
condmeans <- sapply( levels(dds.DESeq$condition), 
                       function(lvl) 
                         rowMeans( counts(dds.DESeq,normalized=TRUE)
                                   [,dds.DESeq$condition == lvl] ) )
head(condmeans)

# Extract Results
DESeqResults <- results(dds.DESeq)

# Add average expression values for each condition to the result table from DESeq2:
DESeqResults.cm <- merge(DESeqResults, condmeans, by="row.names", all.x=TRUE, )

# Change the name of the first column so it matches the geneID column in annotdat (file from Igor @ JGI)
names(DESeqResults.cm)[1] <- "geneID"

# add JGI's annotations to to DESeq output:
merge1 <- merge(DESeqResults.cm, annotdat, by="geneID", all.x=TRUE, )
merge2 <- merge(merge1, ALL_FCdata[, list(geneID, GOname, GOtype, GOid, KEGGid, 
                                                    KEGGdef, KEGGactivity, KEGGpathway, 
                                                    KEGGpathwayclass, KEGGtype)], by="geneID", all.x=TRUE, )
DESeqResults.cm.a <- merge(merge2, FunCatNotes, by="geneID", all.x=TRUE, )

# THERE ARE DUPLICATED GENE_IDs!!! WTF!!
# looks like it's from the FunCatNotes...
FunCatNotes <- unique(FunCatNotes)
FunCatNotes <- na.omit(FunCatNotes)

DESeqResults.cm.a <- unique(DESeqResults.cm.a)

DESeqResults.cm.a[geneID == "gene_1304"]


# How many adjusted p-values are less than your favorite p-value?
sum(DESeqResults$padj < 0.01, na.rm=TRUE)


#################
# Basic MA plot #
#################
DESeqResults.na <- na.omit(DESeqResults)

ggplot(DESeqResults.na, aes(x=baseMean,y=log2FoldChange))+ 
  geom_point(aes(colour=padj<0.01), size=0.3)+
  scale_colour_manual(name='p.adj < 0.01',values=setNames(c('#9540bf','grey80'), c(T,F))) +
  geom_hline(yintercept = c(-2,2), color="#40bf80")+ #turquoise lines at y=2 and y=-2
  geom_hline(yintercept = 0, color="black", alpha=0.5)+ #transparent line at y=0 
  theme(panel.background = element_rect(fill="white"))+ #plot background color
  theme(panel.grid.minor = element_blank())+  #omit default grid on plot
  theme(panel.grid.major = element_blank())+  #omit default grid on plot
  theme(panel.border = element_rect(fill = NA, colour = "black", size = 1))+ #black board around plot
  theme(axis.title.y = element_text(face="bold", size=12))+ #define parameters of y-axis title
  theme(axis.title.x = element_text(face="bold", size=12))+ #define parameters of x-axis title
  theme(plot.title = element_text(face="bold", size=14))+  #define parameters for plot title
  theme(legend.key = element_rect(color = "grey",  fill = "white"))+  
  scale_x_log10()+  #log-scaled x-axis
  scale_y_continuous(breaks=seq(-8, 15, 2), limits = c(-8, 15))+
  ylab("Log2 Fold Change")+ #label for y-axis
  xlab("Mean Expression")+ #label for x-axis
  ggtitle("Water vs. Sucrose")


nrow(DESeqResults.na[DESeqResults.na$padj < 0.01 & DESeqResults.na$log2FoldChange < -2, ]) #94
nrow(DESeqResults.na[DESeqResults.na$padj < 0.01 & DESeqResults.na$log2FoldChange > 2, ]) #318
nrow(DESeqResults.na[DESeqResults.na$padj < 0.01, ])#1013


## THIS DOESNT WORK ANYMORE (not sure why?!)
# indentify specific points on the plot:
idx <- identify(results$baseMean, results$log2FoldChange)
rownames(results)[idx]
# click on the points you want to identify, then hit Escape.

# Circle and label specific points:
FavGene <- rownames(DESeqResults)[which(rownames(DESeqResults)=="NCU05712")]
with(DESeqResults[FavGene, ], {
  points(baseMean, log2FoldChange, col="dodgerblue", cex=2, lwd=2)
  text(baseMean, log2FoldChange, FavGene, pos=2, col="dodgerblue")})


###########################################
### Use ggplot2 to make fancy MA plot! ####
###########################################
# Results file after running DESeq2:
DESeqResults <- results(dds.DESeq, tidy=TRUE)
# Format DESeq File to make it easier to deal with:
DESeqResults <- tbl_df(DESeqResults)

# Load a .txt file that contains a list of genes (e.g. pp-1 targets):
targets <- read.table(file.choose(), header=TRUE)
#targets2 <- list("NCU04732", "NCU00881", "NCU07192", "NCU05712", "NCU05721")

# Before creating the MA plot, add collumns to the DESeqResults file 
# to designate what color the point for each gene should be:

# If foldchange>2 OR foldchange<-2, AND p.adj <0.01, then Col=purple, otherwise Col=orange
DESeqResults$Col = ifelse((DESeqResults$log2FoldChange>(2) | #or
                             DESeqResults$log2FoldChange<(-2) & #and
                             DESeqResults$padj<0.01),"#a500ff", "orange")

# If a gene in the targets file also appears in the DESeqResults file, 
# then outline=black, otherwise NA (NA's will have no outline).
DESeqResults$outline = ifelse((match(DESeqResults$row, targets$ADV1motif)),"black", NA)

# MA plot via ggplot:
DESeqResults %>% 
  ggplot(aes(baseMean, log2FoldChange))+ #x-axis = baseMean, y-axis=log2FoldChange
  geom_point(shape = 21, #shape 21 is a circle with an outline
             #colour=DESeqResults$outline, #point oultine color based on targets
             fill=DESeqResults$Col,       #point fill color based on significance
             size=1.5, #diameter of point
             stroke=1, #thickness of outline
             alpha=0.5)+ #transparency of point (smaller number = more transparent)
  geom_hline(yintercept = c(-2,2), color="#00ffa5")+ #turquoise lines at y=2 and y=-2
  geom_hline(yintercept = 0, color="grey20", alpha=0.5)+ #transparent line at y=0 
  theme(panel.background = element_rect(fill="white"))+ #plot background color
  theme(panel.grid.minor = element_blank())+  #omit default grid on plot
  theme(panel.grid.major = element_blank())+  #omit default grid on plot
  theme(panel.border = element_rect(fill = NA, colour = "black", size = 1))+ #black board around plot
  theme(axis.title.y = element_text(face="bold", size=12))+ #define parameters of y-axis title
  theme(axis.title.x = element_text(face="bold", size=12))+ #define parameters of x-axis title
  theme(plot.title = element_text(face="bold", size=14))+  #define parameters for plot title
  scale_x_log10()+  #log-scaled x-axis
  labs(title="Dpp-1 vs. WT")+ #plot title
  ylab("Log2 Fold Change")+ #label for y-axis
  xlab("Mean Expression") #label for x-axis

#Export as a PDF to maintain transparencies!

#
#
#

########################
#### Venn Diagrams! ####
########################
# Function that will convert an input dataframe into a presence/absence table
vennfun <- function(x) { 
  x$id <- seq(1, nrow(x)) #add a column of numbers that is required by Reshape
  xm <- melt(x, id.vars="id", na.rm=TRUE) #melt table into two columns: variables and values
  xc <- dcast(xm, value~variable, fun.aggregate=length) #list presence/absence of each value for each variable (1 or 0)
  rownames(xc) <- xc$value #make the value column the rownames
  xc$value <- NULL #remove redundent value column
  xc #output the new dataframe
}

# Input dataframe should look something like this:
### Variable1   Variable2   Variable3
### value2      value5      value2
### value7      value8      value8
### etc.        etc.        etc.
# For example, the variables are treatments and the values are genes  
# that are differentially expressed between conditions
library(data.table)
## DIFFERENTIALLY EXPRESSED GENES VS. SUCROSE
DEgenes_v_Sucrose <- fread(file.choose(), na.strings=c("", "NA"))
tail(DEgenes_v_Sucrose)

DEgenes_v_Sucrose.pa <- vennfun(DEgenes_v_Sucrose)

library(eulerr)
DataForVenn <- data.table(cbind(DEgenes_v_Sucrose.pa$char,
                                DEgenes_v_Sucrose.pa$water,
                                DEgenes_v_Sucrose.pa$soil))
DataForVenn[is.na(DataForVenn)] <- 0 #Change NAs to 0s to make eulerr happy!
colnames(DataForVenn) <- c("CharDown", "WaterDown", "ICBdown")

TheVenn <- euler(DataForVenn)
plot(TheVenn, quantities = TRUE, main="downregulated genes vs. Sucrose (log2FC>2)")

####
#print genes associated with a particular section of a VennDiagram:
DEgenes_v_Sucrose$id <- seq(1, nrow(DEgenes_v_Sucrose)) #add a column of numbers that is required by Reshape
DEgenes_v_Sucrose.melt <- melt(DEgenes_v_Sucrose, id.vars="id", na.rm=TRUE) #melt table into two columns: variables and values
DEgenes_v_Sucrose.cast <- dcast(DEgenes_v_Sucrose.melt, value~variable, fun.aggregate=length) #list presence/absence of each value for each variable (1 or 0)
colnames(DEgenes_v_Sucrose.cast)[1] <- "geneID"

nrow(DEgenes_v_Sucrose.cast[char == 1 & 
                            water == 0 &
                            soil == 1
                            , "geneID"])

print <- DEgenes_v_Sucrose.cast[char == 1 & 
                                water == 1 &
                                soil == 0]

print.annot <- merge(print, ALL_FCdata, by="geneID", all.x=TRUE, )

###
##



### VENN of DIFFERENTIALLY EXPRESSED GENES VS. WATER ###
DEgenes_v_Water <- fread(file.choose(), na.strings=c("", "NA"))
tail(DEgenes_v_Water)

DEgenes_v_Water.pa <- vennfun(DEgenes_v_Water)

library(data.table)
library(eulerr)
DataForVenn <- data.table(cbind(DEgenes_v_Water.pa$CharUP,
                                DEgenes_v_Water.pa$SucroseUP))
DataForVenn[is.na(DataForVenn)] <- 0 #Change NAs to 0s to make eulerr happy!
colnames(DataForVenn) <- c("CharUp", "SucroseUP")

TheVenn <- euler(DataForVenn)
plot(TheVenn, quantities = TRUE, main="Number of up-regulated genes vs. Water")

###
#print genes associated with a particular section of a VennDiagram:
DEgenes_v_Water$id <- seq(1, nrow(DEgenes_v_Water)) #add a column of numbers that is required by Reshape
DEgenes_v_Water.melt <- melt(DEgenes_v_Water, id.vars="id", na.rm=TRUE) #melt table into two columns: variables and values
DEgenes_v_Water.cast <- dcast(DEgenes_v_Water.melt, value~variable, fun.aggregate=length) #list presence/absence of each value for each variable (1 or 0)
colnames(DEgenes_v_Water.cast)[1] <- "geneID"

nrow(DEgenes_v_Water.cast[CharUP == 1 & 
                          SucroseUP == 0, 
                          "geneID"])

print <- DEgenes_v_Water.cast[CharUP == 1 & 
                              SucroseUP == 0
                              ]
print.annot <- merge(print, annot, by="geneID", all.x=TRUE, )
##
#

###
###
#



#
#
#####################################
## CREATE MASTER ALL_FCdata TABLE! ##
#####################################
#merge all FC and p.adj values into one massive table!
#note annotdat = 11812 rows... so there are ~2000 genes not expressed under any condition
merge1 <- merge(annotdat, CvS_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(merge1)[c(2,7,8)] <- c("proteinID", "CvS_FC", "CvS_p.adj")

merge2 <- merge(merge1, IvS_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(merge2)[9:10] <- c("IvS_FC", "IvS_p.adj")

merge3 <- merge(merge2, WvS_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(merge3)[11:12] <- c("WvS_FC", "WvS_p.adj") 

#double check this is correct! WvS got confused with SvW at some point!
merge3[geneID=="gene_10080", WvS_FC] #3.0458
WvS_DESeqOutput[geneID=="gene_10080", log2FoldChange] #3.0458

merge4 <- merge(merge3, CvW_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(merge4)[13:14] <- c("CvW_FC", "CvW_p.adj")

merge5 <- merge(merge4, IvW_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(merge5)[15:16] <- c("IvW_FC", "IvW_p.adj")

merge6 <- merge(merge5, CvI_DESeqOutput[ ,list(geneID, log2FoldChange, padj)], by="geneID", all.x=TRUE, )
names(ALL_FCdata)[17:18] <- c("CvI_FC", "CvI_p.adj")

## add GO and KEGG annotations
#GO <- fread(file.choose())
#names(GO)[1] <- "proteinID"
#KEGG <- fread(file.choose())
#names(KEGG)[1] <- "proteinID"

# collapse all GO and KEGG annotations so there is one row per proteinID
# Where there are multiple annotations, they will be delimited by a ";"
GOcollapsed <- setDT(GO)[, .(GOname = paste(goName, collapse = ";"),
                             GOtype = paste(gotermType, collapse = ";"),
                             GOid = paste(gotermId, collapse = ";")), by = .(proteinID)]

KEGGcollapsed <- setDT(KEGG)[, .(KEGGid = paste(ecNum, collapse = ";"),
                                 KEGGdef = paste(definition, collapse = ";"),
                                 KEGGactivity = paste(catalyticActivity, collapse = ";"),
                                 KEGGpathway = paste(pathway, collapse = ";"),
                                 KEGGpathwayclass = paste(pathway_class, collapse = ";"),
                                 KEGGtype = paste(pathway_type, collapse = ";")), by = .(proteinID)]

merge7 <- merge(merge6, GOcollapsed, by="proteinID", all.x=TRUE, )

merge8 <- merge(merge7, KEGGcollapsed, by="proteinID", all.x=TRUE, )

#TPMvalues
merge9 <- merge(merge8, TPM, by="geneID", all.x=TRUE, )

# Add manually currated funcat notes:
#FunCatNotes <- fread(file.choose())
ALL_FCdata <- merge(merge9, FunCatNotes, by="geneID", all.x=TRUE, )

colnames(ALL_FCdata)

##
#
#



#######################################################
#### Barplot of genes associated with Venn Diagram ####
#######################################################
DEgenes <- fread(file.choose())
head(DEgenes)
DEgenes[,3] <- -DEgenes[,3]
head(DEgenes)

library(ggplot2)
ggplot(data=DEgenes, aes(x=GeneFunction, y=GeneCount, fill=Treatment))+
  geom_bar(stat="identity", position=position_dodge())+
  scale_fill_manual(values=c("black","grey50","#0075d6"))+
  ylab("Number of Genes")+
  xlab("Gene Function")+
  theme(axis.ticks.x = element_blank())+
  theme(axis.line.y = element_line(color = "black", linetype = "solid", size=0.4))+
  theme(axis.line.x = element_line(color = "black", linetype = "solid", size=0.4))+
  scale_y_continuous(breaks=seq(0, 80, 10),  limits=c(0,80), expand = c(0,0))+ 
  theme(legend.title = element_text(color="black", size=18, face="bold"))+
  theme(legend.text = element_text(color="black", size = 14))+
  theme(panel.background = element_rect(fill="white"))+
  theme(panel.grid.minor = element_blank())+
  theme(panel.grid.major.y = element_line(color="grey95"))+
  theme(axis.text.x = element_text(angle=45, color="black", size=12, 
                                   hjust=1, vjust=1.0))+
  theme(axis.title.x = element_text(color="black", size=14, face="bold"))+
  theme(axis.title.y = element_text(color="black", size=14, face="bold"))+
  theme(axis.text.y = element_text(color="black", size=11))

##
library(data.table)
FPKMs <- fread(file.choose())
annot <- fread(file.choose())
KEGG <- fread(file.choose())
GO <- fread (file.choose())
names(annot)[2] <- "proteinID"
names(FPKMs)[1] <- "geneID"
names(GO)[1] <- "proteinID"
names(KEGG)[1] <- "proteinID"

GOcollapsed <- setDT(GO)[, .(GOname = paste(goName, collapse = ";"),
                             GOtype = paste(gotermType, collapse = ";"),
                             GOid = paste(gotermId, collapse = ";")), by = .(proteinID)]

KEGGcollapsed <- setDT(KEGG)[, .(KEGGid = paste(ecNum, collapse = ";"),
                                 KEGGdef = paste(definition, collapse = ";"),
                                 KEGGactivity = paste(catalyticActivity, collapse = ";"),
                                 KEGGpathway = paste(pathway, collapse = ";"),
                                 KEGGpathwayclass = paste(pathway_class, collapse = ";"),
                                 KEGGtype = paste(pathway_type, collapse = ";")), by = .(proteinID)]
