-- Shared software policy. This file is copied into every offspring.
return {
  version = '0.5.0-dev',
  mode = 'controller',          -- M2 exploration is explicit opt-in only
  fuelReserve = 24,           -- keep after returning from a survey
  surveyLimit = 12,           -- hard maximum blocks per survey
  logLimitBytes = 16000,
  childFuelItems = 4,         -- coal or charcoal given to each child
}
