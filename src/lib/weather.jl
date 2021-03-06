include("datastore.jl")

"Reorder `values`, currently ordered according to `fromfips`, to `tofips` order."
function reorderfips(values::Union{DataArrays.DataArray{Float64, 1}, Vector{Float64}}, fromfips, tofips)
    result = zeros(length(tofips))
    for rr in 1:length(tofips)
        ii = findfirst(fromfips .== tofips[rr])
        if ii > 0
            result[rr] = values[ii]
        end
    end

    result
end

"Reorder `weather` and transpose, a T x N(`fromfips`) matrix, into a N(`tofips`) x T matrix."
function reorderfips(weather::Array{Float64, 2}, fromfips, tofips)
    result = zeros(length(tofips), size(weather, 1))
    for rr in 1:length(tofips)
        ii = findfirst(fromfips .== tofips[rr])
        if ii > 0
            result[rr, :] = weather[:, ii]
        end
    end

    result
end

"Reorder `weather`, a N(`fromfips`) x T matrix, into a N(`tofips`) x T matrix."
function reorderfips_notranspose(weather::DataFrame, fromfips, tofips)
    result = zeros(length(tofips), size(weather, 2))
    for rr in 1:length(tofips)
        ii = findfirst(fromfips .== tofips[rr])
        if ii > 0
            println(weather[ii, :])
            result[rr, :] = weather[ii, :]
        end
    end

    result
end

"""
Sum values within each timestep, returning a T x N(columns) matrix.

Assumes that `config` is defined globally
"""
function sum2timestep(weather)
    if config["timestep"] == 1
        return weather[get(config, "startweather", 1):get(config, "startweather", 1)+numsteps-1, :]
    end

    bytimestep = zeros(numsteps, size(weather, 2))
    for timestep in 1:numsteps
        allcounties = zeros(1, size(weather, 2))
        for month in 1:config["timestep"]
            allcounties += transpose(weather[round.(Int64, (timestep - 1) * config["timestep"] + month + get(config, "startweather", 1) - 1), :])
        end

        bytimestep[timestep, :] = allcounties
    end

    bytimestep
end

"""
Return a matrix of MONTH x GAUGES (to match order for `sum2timestep`).
Return as 1000 m^3

# Arguments
* `stations::DataFrame`: Contains `lat` and `lon` columns to match up
  with the data; the result matrix will have the same number of rows.
"""
function getadded(stations::DataFrame)
    # Check if the weather file needs to be downloaded
    gage_latitude = knownvariable("runoff", "gage_latitude")
    gage_longitude = knownvariable("runoff", "gage_longitude")
    gage_totalflow = knownvariable("runoff", "totalflow")
    gage_area = knownvariable("runoff", "contributing_area")

    added = zeros(size(gage_totalflow, 2), nrow(stations)) # contributions (1000 m^3)

    for ii in 1:nrow(stations)
        gage = find((abs.(stations[ii, :lat] - gage_latitude) .< 1e-6) .& (abs.(stations[ii, :lon] - gage_longitude) .< 1e-6))
        if length(gage) != 1 || gage[1] > size(gage_totalflow)[1]
            continue
        end

        added[:, ii] = vec(gage_totalflow[gage[1], :]) * gage_area[gage[1]]
    end

    added[isnan.(added)] = 0 # if NaN, set to 0 so doesn't propagate

    added
end

"""
Get the number of steps represented in a weather file.
"""
function getmaxsteps()
    length(knownvariable("runoff", "month"))
end
