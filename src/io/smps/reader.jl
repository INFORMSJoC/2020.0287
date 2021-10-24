# MIT License
#
# Copyright (c) 2018 Martin Biel
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

function Base.read(io::IO, ::Type{SMPSModel})
    raw = read(io, RawSMPS)
    return SMPSModel(raw)
end
"""
    read(io::IO,
         ::Type{SMPSSampler})

Return an `StochasticModel` from the model definition read from `io` in SMPS format.
"""
function Base.read(io::IO, ::Type{StochasticModel})
    smps::SMPSModel{2} = read(io, SMPSModel)
    return stochastic_model(smps)
end
"""
    read(io::IO,
         ::Type{SMPSSampler})

Return an `SMPSSampler` capable of sampling `SMPSScenario` using the model definition read from `io` in SMPS format.
"""
function Base.read(io::IO, ::Type{SMPSSampler})
    smps::SMPSModel{2} = read(io, SMPSModel)
    return SMPSSampler(smps.raw.sto, smps.stages[2])
end
"""
    read(io::IO,
         ::Type{StochasticProgram};
         num_scenarios::Union{Nothing, Integer} = nothing,
         instantiation::StochasticInstantiation = UnspecifiedInstantiation(),
         optimizer = nothing;
         defer::Bool = false,
         kw...)

Instantiate a two-stage stochastic program using the model definition read from `io` in SMPS format, of size `num_scenarios`. If `num_scenarios = nothing`, instantiate using the full support. Optionally, supply an `optimizer`. If no explicit `instantiation` is provided, the structure is induced by the optimizer. The structure is `Deterministic` by default.
"""
function Base.read(io::IO,
                   ::Type{StochasticProgram};
                   num_scenarios::Union{Nothing, Integer} = nothing,
                   instantiation::StochasticInstantiation = StochasticPrograms.UnspecifiedInstantiation(),
                   optimizer = nothing,
                   defer::Bool = false,
                   direct_model::Bool = false,
                   kw...)
    smps::SMPSModel{2} = read(io, SMPSModel)
    sm = stochastic_model(smps)
    sampler = SMPSSampler(smps.raw.sto, smps.stages[2])
    if num_scenarios != nothing
        return instantiate(sm, sampler, num_scenarios; instantiation = instantiation, optimizer = optimizer, defer = defer, direct_model = direct_model, kw...)
    else
        return instantiate(sm, full_support(sampler); instantiation = instantiation, optimizer = optimizer, defer = defer, direct_model = direct_model, kw...)
    end
end
Base.read(filename::AbstractString, ::Type{StochasticProgram}; kw...) = open(io -> read(io, StochasticProgram; kw...), filename)
