
## `config` must be defined before loading this file!

include("world.jl")
include("weather.jl")

include("Thermoelectric.jl")
include("Livestock.jl")
include("Agriculture.jl");
include("IndustrialDemand.jl");
include("UrbanDemand.jl");
include("WaterDemand.jl");
include("PopulationDemand.jl")

## Check if the optimize-surface script has been called
storedresult = cached_fallback("extraction/captures", () -> false)
if storedresult == false
    warn("Missing saved allocation files.  Please run optimize-surface.jl")
elseif size(storedresult)[1] != numreservoirs || size(storedresult)[2] != numsteps
    warn("Cache file does not match current configuration.  Please remove.")
end


println("Creating model...")
model = newmodel();

# Add all of the components
thermoelectric = initthermoelectric(model); # exogenous
livestock = initlivestock(model); # exogenous
agriculture = initagriculture(model); # optimization-only
industrialdemand = initindustrialdemand(model); # exogenous
urbandemand = initurbandemand(model); # exogenous
waterdemand = initwaterdemand(model); # dep. Agriculture, PopulationDemand

# Connect up the components
waterdemand[:totalirrigation] = agriculture[:totalirrigation];
waterdemand[:thermoelectricuse] = thermoelectric[:demand_copy];
waterdemand[:livestockuse] = livestock[:demand_copy];
waterdemand[:urbanuse] = urbandemand[:waterdemand];
waterdemand[:industrialuse] = industrialdemand[:waterdemand];