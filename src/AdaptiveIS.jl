__precompile__()

module AdaptiveIS

using Distributions, Plots

export ais_type, show, ais, plot, plot!

g(z::Vector{Float64},t::Vector{Float64},t0::Vector{Float64})=cdf(Normal(),z-t).*(1.-t0)+exp(-t.*z).*t0
g2(z::Vector{Float64},t::Float64,t0::Float64)=cdf(Normal(),z-t)*(1.-t0)+exp(-t*z)*t0

ginv(u::Vector{Float64},t::Vector{Float64},t0::Vector{Float64})=(quantile(Normal(),u)+t).*(1.-t0)+(-log(u)./(t+1e-5)).*t0
ginv2(u::Vector{Float64},t::Float64,t0::Float64)=(quantile(Normal(),u)+t)*(1.-t0)+(-log(u)/(t+1e-5))*t0

h(u::Vector{Float64},t::Vector{Float64},l::Vector{Float64},t0::Vector{Float64})=exp(sum((-t.*(quantile(Normal(),u)+l)+t.^2/2.).*(1.-t0)+(-log(abs(t+1e-5))+(1.-t)./(l+1e-5).*log(u)).*t0))
h2(u::Vector{Float64},t::Float64,l::Float64,t0::Float64)=exp(t*sum(t/2-l-quantile(Normal(),u))*(1.-t0)+(-length(u)*log(abs(t+1e-5))+(1.-t)/l*sum(log(u)))*t0)

gh(u::Vector{Float64},t::Vector{Float64},l::Vector{Float64},t0::Vector{Float64})=((t-quantile(Normal(),u)-l).*(1.-t0)+(-1./(t+1e-5)-log(u)./(l+1e-5)).*t0)*h(u,t,l,t0)
gh2(u::Vector{Float64},t::Float64,l::Float64,t0::Float64)=(sum(t-l-quantile(Normal(),u))*(1.-t0)+sum(-1/(t+1e-5)-log(u)/(l+1e-5))*t0)*h(u,t,l,t0)

r(u::Vector{Float64},t::Vector{Float64},f::Function,t0::Vector{Float64})=f(g(ginv(u,t,t0),t0,t0))*h(u,t,t,t0)
r2(u::Vector{Float64},t::Float64,f::Function,t0::Float64)=f2(g2(ginv2(u,t,t0),t0,t0))*h2(u,t,t,t0)

gn(u::Vector{Float64},t::Vector{Float64},l::Vector{Float64},f::Function,t0::Vector{Float64})=f(g(ginv(u,l,t0),t0,t0))^2*gh(u,t,l,t0)*h(u,l,l,t0)
gn2(u::Vector{Float64},t::Float64,l::Float64,f::Function,t0::Float64)=f2(g2(ginv2(u,l,t0),t0,t0))^2*gh2(u,t,l,t0)*h2(u,l,l,t0)

function maxd(t::Vector{Float64},lb::Vector{Float64},ub::Vector{Float64})
    d=length(t)
    corner=zeros(d)
    [(t[i]-lb[i])<(ub[i]-t[i]) ? corner[i]=ub[i] : corner[i]=lb[i] for i=1:d]
    return(norm(t-corner))
end
maxd2(t::Float64,lb::Float64,ub::Float64)=max(t-lb,ub-t)

function points(lb::Vector{Float64},ub::Vector{Float64},npart::Int64)
    d=length(lb)
    pts=zeros(d,npart^d)
    [pts[i,:]=repmat(repeat(linspace(lb[i],ub[i],npart)',inner=[1,npart^(d-i)]),1,npart^(i-1)) for i=1:d]
    return(pts)
end

function maxl(l::Vector{Float64},lb::Vector{Float64},ub::Vector{Float64},npart::Int64,sampsize::Int64,f::Function,t0::Vector{Float64})
    d=length(l)
    pts=points(lb,ub,npart)
    L=zeros(npart^d)
    samp=zeros(sampsize)
    for i=1:npart^d
        for j=1:sampsize
            samp[j]=norm(gn(rand(d),pts[:,i],l,f,t0))^2
        end
        L[i]=sqrt(mean(samp))
    end
    return(maximum(L))
end
function maxl2(l::Float64,lb::Float64,ub::Float64,npart::Int64,sampsize::Int64,f::Function,d::Int64,t0::Float64)
    pts=linspace(lb,ub,npart)
    L=zeros(npart)
    samp=zeros(sampsize)
    for i=1:npart
        for j=1:sampsize
            samp[j]=gn2(rand(d),pts[i],l,f,t0)^2
        end
        L[i]=sqrt(mean(samp))
    end
    return(maximum(L))
end

t(z::Vector{Float64},t0::Vector{Float64})=z.*(1.-t0)-z.*t0
t2(z::Vector{Float64},t0::Float64)=sum(z)*(1.-t0)-sum(z)*t0

gq(l::Vector{Float64},t0::Vector{Float64})=-l.*(1.-t0)+1./(l+1e-5).*t0
gq2(l::Float64,d::Int64,t0::Float64)=-d*l*(1.-t0)+d/(l+1e-5)*t0

function saa(u::Vector{Float64},lb::Vector{Float64},ub::Vector{Float64},npart::Int64,f::Function,t0::Vector{Float64})
    d=length(u)
    pts=points(lb,ub,npart)
    samp=zeros(npart^d)
    [samp[i]=h(u,pts[:,i],t0,t0) for i=1:npart^d]
    return(pts[:,findmin(samp)[2]])
end
function saa2(u::Vector{Float64},lb::Float64,ub::Float64,npart::Int64,f::Function,t0::Float64)
    pts=linspace(lb,ub,npart)
    samp=zeros(npart)
    [samp[i]=h(u,pts[i],t0,t0) for i=1:npart]
    return(pts[findmin(samp)[2]])
end

"""
Stores the intermediate values of the empirical mean and importance sampling parameter
as well as the value of the auxiliary parameter.
"""
type ais_type
    "The intermediate values of the empirical mean."
    μ::Vector{Float64}
    "The intermediate values of the importance sampling parameter."
    θ::Array{Float64,2}
    "The value of the auxiliary parameter."
    λ::Vector{Float64}
end

function Base.show(io::IO, ais::ais_type)
    print(io, "Terminal values: μ=$(ais.μ[end]), θ=$(ais.θ[end,:])")
end

"""
    ais(f::Function,d::Int64;<keyword arguments>)

Approximate the expected value of `f` whose domain is the `d`-dimensional hypercube
using adaptive importance sampling, where the importance sampling parameter is updated
using robust stochastic approximation.

# Arguments
* `n::Int64=10^4`: the number of iterations of the Monte Carlo simulation.
* `t0=zeros(d)`: a vector of 1's and 0's of length `d` which specifies the importance
sampling distribution. Each 1 sets the importance sampling distribution to be the
exponential distribution in the corresponding dimension, and each 0 the normal
distribution with unit standard deviation.
* `lb=t0-0.5`: a vector of length `d` which denotes the lower bound of the domain of
the importance sampling parameter in each dimension.
* `ub=t0+0.5`: a vector of length `d` which denotes the upper bound of the domain of
the importance sampling parameter in each dimension.
* `npart::Int64=5`: the number of points to discretise each dimension of the domain of
the importance sampling parameter into. Used in calculating the step size in roust
stochastic approximation and choosing the auxiliary parameter via sample average
approximation.
* `sampsize::Int64=10^2`: the number of samples to generate at each point in the
discretised domain of the importance sampling parameter when calculating the step size
in robust stochastic approximation.
* `accel::AbstractString="none"`: specifies whether an auxiliary parameter is used to
accelerate the Monte Carlo simulation, and if so, the method of choosing the auxiliary
parameter. Useful when the function `f` is zero with a high probability. Accepted
arguments are "`none`", "`directsub`", "`sa`", and "`saa`".
* `dimreduc::Bool=false`: if true, implements dimension reduction of the importance
sampling parameter by restricting all components of the importance sampling parameter
to be equal.

# Example
```jldoctest
julia> using AdaptiveIS
julia> f(x)=mean(x)>=0.85 ? 1. : 0.
julia> srand(5)
julia> ais(f,3)
Terminal values: μ=0.015014809526721174, θ=1x3 Array{Float64,2}:
 0.226725  0.234437  0.230236
```
"""
function ais(f::Function,d::Int64;n::Int64=10^4,t0=zeros(d),lb=t0-0.5,ub=t0+0.5,npart::Int64=5,sampsize::Int64=10^2,accel::AbstractString="none",dimreduc::Bool=false)
    if dimreduc==false
    if d<1
        error("The dimension of the problem should be positive.")
    end
    if n<1
        error("n should be positive.")
    end
    if length(t0)!=d
        error("length(t0) should match the dimension of the problem.")
    end
    t0=ones(d).*t0
    if t0.^2!=t0
        error("t0 should only contain 0's and 1's.")
    end
    if length(lb)!=d
        error("length(lb) should match the dimension of the problem.")
    end
    lb=ones(d).*lb
    if length(ub)!=d
        error("length(ub) should match the dimension of the problem.")
    end
    ub=ones(d).*ub
    if sum(lb.<=t0.<=ub)!=d
        error("lb should be smaller than or equal to ub and they should contain t0.")
    end
    if sum((lb.*t0).>0.)!=sum(t0)
        error("Whenever t0 is 1, lb should be positive.")
    end
    if npart<2
        error("npart should be at least 2.")
    end
    if sampsize<1
        error("sampsize should be positive.")
    end
    
    rsamp=zeros(n)
    θ=repmat(t0,1,n+1)
    
    if accel=="none"
        step=maxd(t0,lb,ub)/(maxl(t0,lb,ub,npart,sampsize,f,t0)*sqrt(n))*sqrt(sum(1./(1:n)))
        for i=1:n
            u=rand(d)
            rsamp[i]=r(u,mean(θ[:,1:i],2)[1:end],f,t0)
            θ[:,i+1]=min(max(θ[:,i]-step*f(u)^2*gh(u,θ[:,i],t0,t0),lb),ub)
        end
        μ=cumsum(rsamp)./(1:n)
        θbar=cumsum(θ[:,1:n],2)./repmat((1:n)',d,1)
        return(ais_type(μ,θbar',t0))
        
    elseif accel=="directsub" || accel=="sa" || accel=="saa"
        tau=0
        u=0.
        temp=0.
        λ=copy(t0)
        while temp==0. && tau!=n
            tau=tau+1
            u=rand(d)
            temp=f(u)
            rsamp[tau]=temp
        end
        if tau==n
            μ=cumsum(rsamp)./(1:n)
            return(ais_type(μ,(θ[:,1:n])',t0))
        end
        θ[:,tau+1]=min(max(t0-temp^2*gh(u,t0,t0,t0)/tau^0.7,lb),ub)
        newt0=mean(θ[:,1:tau+1],2)[1:end]
        θ[:,tau+1]=copy(newt0)
        if accel=="directsub"
            λ=copy(newt0)
        elseif accel=="sa"
            λ=min(max(t0+(t(ginv(u,t0,t0),t0)+gq(t0,t0))/tau^0.7,lb),ub)
        else
            λ=saa(u,lb,ub,npart,f,t0)
        end
        step=maxd(newt0,lb,ub)/(maxl(λ,lb,ub,npart,sampsize,f,t0)*sqrt(n-tau))*sqrt(sum(1./(1:n-tau)))
        for i=tau+1:n
            u=rand(d)
            rsamp[i]=r(u,mean(θ[:,tau+1:i],2)[1:end],f,t0)
            θ[:,i+1]=min(max(θ[:,i]-step*gn(u,θ[:,i],λ,f,t0),lb),ub)
        end
        μ=cumsum(rsamp)./(1:n)
        θbar=hcat(repmat(t0,1,tau),cumsum(θ[:,tau+1:n],2)./repmat((1:n-tau)',d,1))
        return(ais_type(μ,θbar',λ))
        
    else
        error("The acceleration method specified is not valid. Choose from none, directsub, sa, and saa.")
    end
    
    else
    if d<1
        error("The dimension of the problem should be positive.")
    end
    if n<1
        error("n should be positive.")
    end
    t0=convert(Float64,t0[1])
    if t0^2!=t0
        error("When using dimension reduction, t0 should be either 0 or 1.")
    end
    lb=convert(Float64,lb[1])
    ub=convert(Float64,ub[1])
    if (lb<=t0<=ub)==false
        error("lb should be smaller than or equal to ub and they should contain t0.")
    end
    if t0==1. && lb<=0.
        error("When using dimension reduction, if t0 is 1,then lb should be positive.")
    end
    if npart<2
        error("npart should be at least 2.")
    end
    if sampsize<1
        error("sampsize should be positive.")
    end
    
    rsamp=zeros(n)
    θ=t0*ones(n+1)
    
    if accel=="none"
        step=maxd2(t0,lb,ub)/(maxl2(t0,lb,ub,npart,sampsize,f,d,t0)*sqrt(n))*sqrt(sum(1./(1:n)))
        for i=1:n
            u=rand(d)
            rsamp[i]=r2(u,mean(θ[1:i]),f,t0)
            θ[i+1]=min(max(θ[i]-step*f(u)^2*gh2(u,θ[i],t0,t0),lb),ub)
        end
        μ=cumsum(rsamp)./(1:n)
        θbar=cumsum(θ[1:n])./(1:n)
        return(ais_type(μ,θbar,t0))
        
    elseif accel=="directsub" || accel=="sa" || accel=="saa"
        tau=0
        u=0.
        temp=0.
        λ=copy(t0)
        while temp==0. && tau!=n
            tau=tau+1
            u=rand(d)
            temp=f(u)
            rsamp[tau]=temp
        end
        if tau==n
            μ=cumsum(rsamp)./(1:n)
            return(ais_type(μ,θ[1:n],t0))
        end
        θ[tau+1]=min(max(t0-temp^2*gh2(u,t0,t0,t0)/tau^0.7,lb),ub)
        newt0=mean(θ[1:tau+1])
        θ[tau+1]=copy(newt0)
        if accel=="directsub"
            λ=copy(newt0)
        elseif accel=="sa"
            λ=min(max(t0+(t2(ginv2(u,t0,t0),t0)+gq2(t0,d,t0))/tau^0.7,lb),ub)
        else
            λ=saa2(u,lb,ub,npart,f,t0)
        end
        step=maxd2(newt0,lb,ub)/(maxl2(λ,lb,ub,npart,sampsize,f,d,t0)*sqrt(n-tau))*sqrt(sum(1./(1:n-tau)))
        for i=tau+1:n
            u=rand(d)
            rsamp[i]=r2(u,mean(θ[tau+1:i]),f,t0)
            θ[i+1]=min(max(θ[i]-step*gn2(u,θ[i],λ,f,t0),lb),ub)
        end
        μ=cumsum(rsamp)./(1:n)
        θbar=vcat(t0*ones(tau),cumsum(θ[tau+1:n])./(1:n-tau))
        return(ais_type(μ,θbar,λ))
        
    else
        error("The acceleration method specified is not valid. Choose from none, directsub, sa, and saa.")
    end
    end
end

function Plots.plot!(ais::ais_type)
    plot!(ais.μ)
end

Plots.plot(ais::ais_type) = (plot();plot!(ais))

end
