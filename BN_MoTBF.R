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

