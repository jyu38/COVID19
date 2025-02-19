library(tidyverse)
library(magrittr)
library(lubridate)
library(tibble)
library(ggplot2)
library(ggthemes)
library(hrbrthemes)
library(rvest)
library(gt)
library(deSolve)
library(EpiEstim)
library(incidence)
library(distcrete)
library(epitrix)
library(projections)
library(dse)
library(rmutil)
library(data.table)
#expanded model-add time element to unvaccinated and vaccinated transitions to Recovered or Dead compartments
pmodel <- function(time, init, parameters) {
  with(as.list(c(init, parameters)), {
    dSv <- -beta1 * Iv * Sv / N + alpha * R + epsilon * sigma * Su / N
    dSu <- -beta2 * Iu * Su / N - epsilon * (1-sigma) * Su / N - epsilon * sigma * Su / N
    dIv <-  beta1 * Iv * Sv / N - (1-kappa1) * lambda1 * Iv - kappa1 * rho1 * Iv
    dIu <-  beta2 * Iu * Su / N - (1-kappa2) * rho1 * Iu - kappa2 * rho2 * Iu
    dR <- (1-kappa1) * lambda1 * Iv + (1-kappa2) * lambda2 * Iu - alpha * R + epsilon * (1-sigma) * Su / N
    dD <- kappa1 * rho1 * Iv + kappa2 * rho2 * Iu
    
    return(list(c(dSv, dSu, dIv, dIu, dR, dD)))
  })
}
covidvax <- read.csv("covid19postvaxstatewidestats.csv")
head(covidvax$date, 50)
#add total cases column
covidvax <- covidvax %>%
  mutate(total_cases = unvaccinated_cases + vaccinated_cases)
covidvax <- covidvax %>%
  mutate(Submission_Date = as.Date(date))
#population 
N <- covidvax$population[151] #total population on July 1
N_vax <- covidvax$population_vaccinated
N_unvax <- covidvax$population_unvaccinated
#exploratory data analysis
daily_cases_plot <- covidvax %>%
  ggplot(aes(x=Submission_Date,y=total_cases)) + geom_point()  +  
  labs(y="Daily Cases", x = "Submission Date",
       title="COVID-19 Observed Daily Incidence, State of California",
       subtitle = "Beginning February 1, 2021")
daily_cases_plot

#cumulative data and plot
covidvax <- covidvax %>%
  mutate("cum_cases" = cumsum(total_cases))
cum_tot_cases_plot <- covidvax %>%
  ggplot(aes(x=Submission_Date,y=cum_cases)) + geom_point()  +  
  labs(y="Cumulative Cases", x = "Submission Date",
       title="COVID-19 Observed Cumulative Incidence, State of California",
       subtitle = "Beginning February 1, 2021")
covidvax <- covidvax %>%
  mutate(total_deaths = unvaccinated_deaths + vaccinated_deaths)
cum_tot_cases_plot

covidvax <- covidvax %>%
  mutate(population = population_unvaccinated + population_vaccinated)
covidvax <- covidvax %>%
  mutate(cum_unvax_deaths = cumsum(unvaccinated_deaths))
covidvax <- covidvax %>%
  mutate(cum_vax_deaths = cumsum(vaccinated_deaths))
covidvax <- covidvax %>%
  mutate(cum_unvax_deaths = cumsum(unvaccinated_deaths))
#vax data

covidvax <- covidvax %>%
  mutate(cum_vax = cumsum(vaccinated_cases))
cum_vax_cases_plot <- covidvax %>%
  ggplot(aes(x=Submission_Date,y=cum_vax)) + geom_point()  +  
  labs(y="Cumulative Cases", x = "Submission Date",
       title="COVID-19 Vaccinated Observed Cumulative Incidence, State of California",
       subtitle = "Beginning February 1, 2021")
cum_vax_cases_plot
#unvax data
head(covidvax$unvaccinated_cases,100)
covidvax <- covidvax %>%
  mutate(cum_unvax = cumsum(unvaccinated_cases))
cum_unvax_cases_plot <- covidvax %>%
  ggplot(aes(x=Submission_Date,y=cum_unvax)) + geom_point()  +  
  labs(y="Cumulative Cases", x = "Submission Date",
       title="COVID-19 Unvaccinated Cumulative Incidence, State of California",
       subtitle = "Beginning February 1, 2021")
cum_unvax_cases_plot
#I compartments
which(colnames(covidvax) == "cum_vax")
#covidvax$I_vax_active <- c(rep(NA, length.out = 18),covidvax[19:nrow(covidvax), 25] - covidvax[1:(nrow(covidvax)-1), 25])

setDT(covidvax)[,I_vax_active:=cum_vax-shift(cum_vax,18,type="lag")]
covidvax$I_vax_active
setDT(covidvax)[,I_unvax_active:=cum_unvax-shift(cum_vax,18,type="lag")]
covidvax$I_unvax_active
#R compartment
covidvax <- covidvax %>%
  mutate(R_vax = cum_vax - cum_vax_deaths) %>%
  mutate(R_vax = lag(R_vax, 18)) %>%
  na.omit()
covidvax$R_vax
covidvax <- covidvax %>%
  mutate(R_unvax = cum_unvax - cum_unvax_deaths) %>%
  mutate(R_unvax = lag(R_unvax, 18)) %>%
  na.omit()
covidvax$R_unvax
covidvax <- covidvax %>%
  mutate(R_total = R_vax + R_unvax)
covidvax$R_total

july <- covidvax %>%
  filter(Submission_Date >="2021-07-01" & Submission_Date <= "2021-7-31")
july_vax_death <- july %>%
  pull(cum_vax_deaths)
july <- july %>%
  mutate(time=1:31)

july$date
Day <- 1:(length(july))
which(covidvax$Submission_Date == "2021-07-01") #151

#figuring out initial conditions
july$I_vax_active[1] #3476 for Iv
july$I_unvax_active[1] #315837 for Iu
july$R_total[1] #303812 for R
july$cum_vax_deaths[1] + july$cum_unvax_deaths[1] #9523 for D
july$population_vaccinated[1] - july$cum_vax[1] #20291966 for Sv
july$population_unvaccinated[1] - july$cum_unvax[1] #11012058 for Su

#variable definitions
#beta1: infection rate from susceptible-vaccinated (Sv) to infected-vaccinated (Iv)
#beta2: infection rate from susceptible-unvaccinated (Su) to infected-unvaccinated (Iu)
#kappa1: case fatality rate for infected-vaccinated
#kappa2: case fatality rate for infected-unvaccinated
#rho1: inverse of time to death-vaccinated
#rho2: inverse of time to death-unvaccinated
#epsilon: vaccination rate 
#sigma: vaccine inefficacy rate
#set up parameters
init <- c(Sv = 20291966, Su = 11012058, Iv = 3476, Iu = 315837, R = 303812, D = 9523)
parameters <- c(N = 34218000, beta1 = 0.355, beta2 = 0.130, kappa1 = 0.0183, kappa2 = 0.0118, epsilon = 9.904923e-06, sigma = 0.05, rho1 = 0.0333, rho2 = 0.0144, alpha = 1/183, lambda1=0.134, lambda2=0.00380)
#beta1 = 0.355, beta2 = 0.130
times      <- seq(0, 500, by = 1)
#solve the system of ODE's
out <- ode(y = init, times = times, func = pmodel, parms = parameters)
#convert to dataframe
out <- as.data.frame(out)
#check values
head(out, 100)
#visualize
pmodel_graph_july <- out %>%
  ggplot(aes(x = times)) +
  labs(y="Individuals",
       x="Time",
       title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Sv, color = "Susceptible-vaccinated")) +
  geom_line(aes(y= Su, color = "Susceptible-unvaccinated")) +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                     breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                     values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
pmodel_graph_july

#see if July data matches

times_31 <- seq(1, 31, by = 1)
#solve the system of ODE's
out_2 <- ode(y = init, times = times_31, func = pmodel, parms = parameters)
#convert to dataframe
out_2 <- as.data.frame(out_2)
pmodel_graph_july_with_data <- ggplot(out_2, aes(x=times_31)) +
  labs(y="Individuals",
       x="Time",
       title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Sv, color = "Susceptible-vaccinated")) +
  geom_line(aes(y= Su, color = "Susceptible-unvaccinated")) +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  geom_point(data = july, aes(y = population_vaccinated - cum_vax, color = "Susceptible-vaccinated")) +
  geom_point(data = july, aes(y = population_unvaccinated - cum_unvax, color = "Susceptible-unvaccinated")) +
  geom_point(data = july, aes(y = I_vax_active, color = "Infectious-vaccinated")) +
  geom_point(data = july, aes(y = I_unvax_active, color = "Infectious-unvaccinated")) +
  geom_point(data = july, aes(y = R_total, color = "Recovered")) +
  geom_point(data = july, aes(y = cum_vax_deaths + cum_unvax_deaths, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                     breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                     values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
  pmodel_graph_july_with_data
#lines are simulated, points are actual values

pmodel_graph_july_with_data_no_S <- ggplot(out_2, aes(x=times_31)) +
  labs(y="Individuals",
        x="Time",
        title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  geom_point(data = july, aes(y = I_vax_active, color = "Infectious-vaccinated")) +
  geom_point(data = july, aes(y = I_unvax_active, color = "Infectious-unvaccinated")) +
  geom_point(data = july, aes(y = R_total, color = "Recovered")) +
  geom_point(data = july, aes(y = cum_vax_deaths + cum_unvax_deaths, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                      breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                      values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
pmodel_graph_july_with_data_no_S
  
  
  
  
  
#so now the values fit pretty well, but nothing really matches Iu very well. I'm going to see how the values compare if I use data values from July to August
july_aug <- covidvax %>%
  filter(Submission_Date >="2021-07-01" & Submission_Date <= "2021-8-31")
july_aug <- july_aug %>%
  mutate(time=1:62)
#variable definitions
#beta1: infection rate from susceptible-vaccinated (Sv) to infected-vaccinated (Iv)
#beta2: infection rate from susceptible-unvaccinated (Su) to infected-unvaccinated (Iu)
#kappa1: case fatality rate for infected-vaccinated
#kappa2: case fatality rate for infected-unvaccinated
#rho1: inverse of time to death-vaccinated
#rho2: inverse of time to death-unvaccinated
#epsilon: vaccination rate 
#sigma: vaccine inefficacy rate
#set up parameters
init <- c(Sv = 20291966, Su = 11012058, Iv = 3476, Iu = 315837, R = 303812, D = 9523)
parameters_ja <- c(N = 34218000, beta1 = 0.355, beta2 = 0.143, kappa1 = 0.0183, kappa2 = 0.0118, epsilon = 9.904923e-06, sigma = 0.05, rho1 = 0.0333, rho2 = 0.0144, alpha = 1/183, lambda1=0.134, lambda2=0.00380)
times      <- seq(0, 500, by = 1)
#solve the system of ODE's
out_ja <- ode(y = init, times = times, func = pmodel, parms = parameters_ja)
#convert to dataframe
out_ja <- as.data.frame(out_ja)
#check values
head(out_ja, 100)
#visualize
pmodel_graph_july_aug <- out_ja %>%
  ggplot(aes(x = times)) +
  labs(y="Individuals",
       x="Time",
       title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Sv, color = "Susceptible-vaccinated")) +
  geom_line(aes(y= Su, color = "Susceptible-unvaccinated")) +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                     breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                     values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
pmodel_graph_july_aug

#see if July and August data matches

times_62 <- seq(1, 62, by = 1)
#solve the system of ODE's
out_ja_2 <- ode(y = init, times = times_62, func = pmodel, parms = parameters_ja)
#convert to dataframe
out_ja_2 <- as.data.frame(out_ja_2)
pmodel_graph_july_aug_with_data <- ggplot(out_ja_2, aes(x=times_62)) +
  labs(y="Individuals",
       x="Time",
       title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Sv, color = "Susceptible-vaccinated")) +
  geom_line(aes(y= Su, color = "Susceptible-unvaccinated")) +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  geom_point(data = july_aug, aes(y = population_vaccinated - cum_vax, color = "Susceptible-vaccinated")) +
  geom_point(data = july_aug, aes(y = population_unvaccinated - cum_unvax, color = "Susceptible-unvaccinated")) +
  geom_point(data = july_aug, aes(y = I_vax_active, color = "Infectious-vaccinated")) +
  geom_point(data = july_aug, aes(y = I_unvax_active, color = "Infectious-unvaccinated")) +
  geom_point(data = july_aug, aes(y = R_total, color = "Recovered")) +
  geom_point(data = july_aug, aes(y = cum_vax_deaths + cum_unvax_deaths, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                     breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                     values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
pmodel_graph_july_aug_with_data
#lines are simulated, points are actual values

pmodel_graph_july_aug_with_data_no_S <- ggplot(out_ja_2, aes(x=times_62)) +
  labs(y="Individuals",
       x="Time",
       title="Modified SIRD Vaccination Model, Simulated") +
  geom_line(aes(y= Iv, color = "Infectious-vaccinated")) +
  geom_line(aes(y= Iu, color = "Infectious-unvaccinated")) +
  geom_line(aes(y= R, color = "Recovered")) +
  geom_line(aes(y= D, color = "Dead")) +
  geom_point(data = july_aug, aes(y = I_vax_active, color = "Infectious-vaccinated")) +
  geom_point(data = july_aug, aes(y = I_unvax_active, color = "Infectious-unvaccinated")) +
  geom_point(data = july_aug, aes(y = R_total, color = "Recovered")) +
  geom_point(data = july_aug, aes(y = cum_vax_deaths + cum_unvax_deaths, color = "Dead")) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(name = "",
                     breaks = c("Susceptible-vaccinated", "Susceptible-unvaccinated", "Infectious-vaccinated", "Infectious-unvaccinated", "Recovered", "Dead"),
                     values = c("red", "orange", "black", "brown", "green", "blue")) + theme_bw()
pmodel_graph_july_aug_with_data_no_S
#slightly different rates if using the July-Aug model. Some rates model the data better than others.
#For July data:
#parameters <- c(N = 34218000, beta1 = 0.355, beta2 = 0.130, kappa1 = 0.0183, kappa2 = 0.0118, epsilon = 9.904923e-06, sigma = 0.05, rho1 = 0.0333, rho2 = 0.0144, alpha = 1/183, lambda1=0.134, lambda2=0.00380)
#For July-August data:
#parameters_ja <- c(N = 34218000, beta1 = 0.355, beta2 = 0.143, kappa1 = 0.0183, kappa2 = 0.0118, epsilon = 9.904923e-06, sigma = 0.05, rho1 = 0.0333, rho2 = 0.0144, alpha = 1/183, lambda1=0.134, lambda2=0.00380)
#the only difference is in beta2
#now to play with the vaccination rate(epsilon) and see what happens
#I think I will just use July data rates.