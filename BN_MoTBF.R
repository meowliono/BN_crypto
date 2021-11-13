#Import data
crypto_gardia<-read.csv("/Users/yiraozhang/Desktop/BN_Crypto/CryptoGardia.csv")
turbidity_ecoli<-read.csv("/Users/yiraozhang/Desktop/BN_Crypto/TurbidityEcoli.csv")
prec<-read.csv("/Users/yiraozhang/Desktop/BN_Crypto/rainfall.csv")
#Select relevant variables
prec<-select(prec,"Date","PRCP","SNOW","TMAX","TMIN","TOBS")
prec<-prec[is.na(prec$TOBS)==0,]
prec<-prec %>%group_by(Date) %>% summarise_each(funs(mean))
#Merge three datasets by date
library(dplyr)
data <- merge(crypto_gardia, turbidity_ecoli,by=c("Date","Site"))%>%merge(prec, by="Date")%>%select( "Date","Giardia...50L","Cryptosporidium...50L","Qualifiers","Average.24hrTurbidity.NTU.","Coliform..Fecal.fc.100mL.","PRCP","SNOW")
df<-merge(data, prec, by="Date")
df<-subset(df,Giardia...50L!="Cancel")
df<-select(df,"Giardia...50L","Average.24hrTurbidity.NTU.","Coliform..Fecal.fc.100mL.","PRCP","TOBS")
colnames(df) <- c("Source","Turbidity","Ecoli","Precipitation","Temperature")
write.csv(df,"/Users/yiraozhang/Desktop/BN_Crypto/combined.csv")
#Ecoli data preprocess
df$Source<-as.numeric(df$Source)
df$Ecoli<-sub("<1","0",df$Ecoli)
for (i in 1:length(df$Ecoli)) {
  if(substring(df$Ecoli[i],1,1)=="E"){
    df$Ecoli[i]=sub(".", "", df$Ecoli[i])
  }
}
df$Ecoli<-as.numeric(df$Ecoli)
#Data augmentation
#Assume the probability of drinking water treatment plant breakdown is 0.01; Add a column "Treatment"
#by generating random variable from Bernoulli distribution B(368, 0.99) (368 is the data size)
set.seed(100)
df$Treatment<-rbinom(length(df$Source),1,0.99)
df$Treatment<-as.character(df$Treatment)
#Drinking water consumption follows gamma distribution shape = 3.938; rate = 0.791: in glasses equalling 200 ml)(Säve-Söderbergh et al., 2018)
#Add a column"Consumption" by generating random variable from Gamma distribution Gamma(3.938, 0.791)*0.2
df$Consumption<-rgamma(length(df$Source),3.938, 0.791)*0.2
#Daily Exposure
#Add a column "Dexposure" denoting daily exposure to Giardia
#If the treament plant it working normally, there will be a 3log removal of Giardia(source/1000)
#Dexposure = Source/1000 * Consumption/50 (the unit of Giardia in source water is cysts/50L)
#If treament plant break down there will be no removal of Giardia
#Dexposure = Source * Consimption/50
for (i in 1:length(df$Ecoli)) {
  if(df$Treatment[i]==1){
    df$Dexposure[i]=df$Source[i]*(1/1000)*df$Consumption[i]*(1/50)
  }
  else{
    df$Dexposure[i]=df$Source[i]*df$Consumption[i]*(1/50)
  }
}
#Annual Exposure
#Aexposure denotes annual exposure to Giardia
#Aexposure = Dexposure * 365
for (i in 1:length(df$Ecoli)) {
  if(df$Treatment[i]==1){
    df$Aexposure[i]=df$Source[i]*(1/1000)*df$Consumption[i]*(1/50)*365
  }
  else{
    df$Aexposure[i]=df$Source[i]*df$Consumption[i]*(1/50)*365
  }
}
#Daily Risk of Infection
#P= 1 - exp (- rD), where P is the individual daily probability of infection, r is an organism-specific infectivity parameter (host-microorganism interaction), 
#and D is the daily ingested dose of parasites. For Giardia, r = 0.02
df$DInfection<-1-exp(-0.02*df$Dexposure)
#Annual Risk of Infection
#P(annual)=1-(1-DInfection)^365
df$AInfection<-1-(1-df$DInfection)^365
#Daily Risk of Illness
#Case to infection ratio of Giardia is 0.4
df$DIllness<-df$DInfection*0.4
#Annual Risk of Illness
df$AIllness<-df$AInfection*0.4
#Daily Risk level>0.00001(0.001%)
df$Dlevel<-cut(df$DIllness,breaks=c(-Inf,0.00001,Inf),labels=c("<0.001%",">=0.001%"))
df$Dlevel<-as.character(df$Dlevel)
#DALY(Disability-adjusted life years)
#DALY=LYL(life-years-lost)+YLD(years lived with a disability)
#LYL = (life expectancy − age at death) × severity weight × outcome fraction
#YLD per case = Σ Outcome fraction(duration of illness × severity weight)
#The DALYs per person per year is then calculated by multiplying the probability of illness per person per year by the DALYs per case of illness for each pathogen. 
df$DALY<-((80.88-38.98)*1*0.00001+0.01918*0.067*0.99999)*df$AIllness
#Make two data sets: daily and annual
#Daily&Annual
df_daily<-df[, -c(9, 11, 13, 15, 16)]
df_annual<-df[,-c(8, 10, 12, 14)]
#MoTBFs learning
library(MoTBFs)
library(bnlearn)
net_daily<-model2network("[Precipitation][Temperature][Source|Precipitation:Temperature][Turbidity|Source][Ecoli|Source][Treatment][Consumption][Dexposure|Treatment:Consumption:Source][DInfection|Dexposure][DIllness|DInfection][Dlevel|DIllness]")
net_annual<-model2network("[Precipitation][Temperature][Source|Precipitation:Temperature][Turbidity|Source][Ecoli|Source][Treatment][Consumption][Aexposure|Treatment:Consumption:Source][AInfection|Aexposure][AIllness|AInfection][DALY|AIllness]")
plot(net_daily)
plot(net_annual)
bn_daily<-MoTBFs_Learning(net_daily, data = df_daily, numIntervals = 4, POTENTIAL_TYPE = "MTE")
bn_annual<-MoTBFs_Learning(net_annual, data = df_annual, numIntervals = 4, POTENTIAL_TYPE = "MTE")
#Model validation
#Generating univariate(Turbidity in this case) by the MoTBFs function
#Compare the generated turbidity values and the actual values
#Examine both visually and by Kolmogorov-Smirnov test
f <- univMoTBF(df_daily[,2], POTENTIAL_TYPE = "MTE", nparam = 13)
X <- rMoTBF(size = 400, fx = f)
hist(X, prob = TRUE, col = "deepskyblue3", main = "", ylim = c(0,2.2))
hist(df_daily[,2], prob = TRUE, col = adjustcolor("gold",alpha.f = 0.5), add = TRUE)
plot(ecdf(df_daily[,2]), cex = 0, main = "")
plot(integralMoTBF(f), xlim = range(df_daily[,2]), col = "red", add = TRUE)
ks.test(df_daily[,2], X)
#Simulations for source
#randomly pick a record
n <- sample(1:length(df_daily$Source),1)
#observations are the values of rest variables
obs <- data.frame(Precipitation=df_daily$Precipitation[n],Temperature=df_daily$Temperature[n],Turbidity=df_daily$Turbidity[n], Ecoli=df_daily$Ecoli[n], Dexposure=df_daily$Dexposure[n])
#node to be predicted is "Source"
node <- "Source"
set.seed(10)
#generate simulations by forward sampling
simulation_source<-forward_sampling(bn_daily, net_daily, target = node, evi = obs, size = 400, maxParam = 15)
#Histograms of generations and add a vertical line(actual source value of the record) 
hist(simulation_source$sample$Source)
abline(v=df_daily$Source[n], col="red")
#Probability Contour
#the joint probability of turbidity and source(source is the only parent of turbidity and turbidity does not have child)
parameters <- parametersJointMoTBF(X = df_daily[,c("Turbidity","Source")],dimensions = c(5,5))
P <- jointMoTBF(parameters)
plot(P, data = df_daily[,c("Turbidity","Source")],  filled = TRUE)
#Climate change simulations
#randomly sample 10 data records and increase temperature by 0.5, 1, 1.5
#df_rep1, df_rep2, df_rep3
#observations are temperature and precipitation
#forward sampling 50 times and calcualte the mean as the DALY of each record
set.seed(100)
n<-sample(1:368, 10)
df_rep1<-df_annual[n,]
df_rep1$Temperature<-df_annual[n,]$Temperature+0.5
df_rep1$Precipitaion<-df_annual[n,]$Precipitation
for (i in 1:length(df_rep$Source)) {
  obs <- data.frame(Temperature=df_rep1$Temperature[i],Precipitaion=df_rep1$Precipitation[i],Treatment=df_rep1$Treatment[i],Consumption=df_rep1$Consumption[i])
  node <-c("DALY")
  simulation<-forward_sampling(bn_annual, net_annual, target = node, evi = obs, size = 50, maxParam = 15)
  df_rep1$DALY[i]<-mean(simulation$sample$DALY)
}
df_rep2<-df_annual[n,]
df_rep2$Temperature<-df_annual[n,]$Temperature+1
df_rep2$Precipitaion<-df_annual[n,]$Precipitation
for (i in 1:length(df_rep2$Source)) {
  obs <- data.frame(Temperature=df_rep2$Temperature[i],Precipitaion=df_rep2$Precipitation[i],Treatment=df_rep2$Treatment[i],Consumption=df_rep2$Consumption[i])
  node <-c("DALY")
  simulation<-forward_sampling(bn_annual, net_annual, target = node, evi = obs, size = 50, maxParam = 15)
  df_rep2$DALY[i]<-mean(simulation$sample$DALY)
}
df_rep3<-df_annual[n,]
df_rep3$Temperature<-df_annual[n,]$Temperature+1.5
df_rep3$Precipitaion<-df_annual[n,]$Precipitation
for (i in 1:length(df_rep3$Source)) {
  obs <- data.frame(Temperature=df_rep3$Temperature[i],Precipitaion=df_rep3$Precipitation[i],Treatment=df_rep3$Treatment[i],Consumption=df_rep3$Consumption[i])
  node <-c("DALY")
  simulation<-forward_sampling(bn_annual, net_annual, target = node, evi = obs, size = 50, maxParam = 15)
  df_rep3$DALY[i]<-mean(simulation$sample$DALY)
}
#df_rep1$DALY, df_rep2$DALY,df_rep3$DALY are the desired values
#Density plot, histograms, boxplots of the DALY of df_rep1, df_rep2, df_rep3
x <- data.frame(T1=df_rep1$DALY,T2=df_rep2$DALY,T3=df_rep3$DALY)
library(ggplot2)
library(reshape2)
data<- melt(x)
ggplot(data,aes(x=value, fill=variable)) + geom_density(alpha=0.25)
ggplot(data,aes(x=value, fill=variable)) + geom_histogram(alpha=0.25)
ggplot(data,aes(x=variable, y=value, fill=variable)) + geom_boxplot()
#Daily Heavy rainfall
#observation is the average daily precipitation plus 30mm
obs <- data.frame(Precipitation=mean(df_daily$Precipitation)+30)
node <- "DInfection"
set.seed(13)
simulation_dlevel<-forward_sampling(bn_daily, net_daily, target = node, evi = obs, size = 400, maxParam = 15)
mean(simulation_dlevel$sample$DInfection)
mean(df_daily$DInfection)
#Water Treatment Plant Breakdown
#observation is treatment=0
obs <- data.frame(Treatment=0)
node <- "DInfection"
set.seed(15)
simulation_dlevel<-forward_sampling(bn_daily, net_daily, target = node, evi = obs, size = 400, maxParam = 15)
mean(simulation_dlevel$sample$DInfection)
mean(df_daily$DInfection)