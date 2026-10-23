-- Shared software policy. This file is copied into every offspring.
return {
  version = '0.3.2',
  mode = 'lab',                 -- no autonomous exploration in v0.1
  fuelReserve = 24,           -- keep after returning from a survey
  surveyLimit = 12,           -- hard maximum blocks per survey
  logLimitBytes = 16000,
  childFuelItems = 4,         -- coal or charcoal given to each child
}
