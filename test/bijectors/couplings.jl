using Test
using Bijectors
using Random
using LinearAlgebra
using ForwardDiff
using Tracker
import Flux

using Bijectors:
    Coupling,
    PartitionMask,
    coupling,
    couple,
    partition,
    combine,
    Shift

@testset "Coupling" begin
    @testset "PartitionMask" begin
        m1 = PartitionMask(3, [1], [2])
        m2 = PartitionMask(3, [1], [2], [3])

        @test (m1.A_1 == m2.A_1) & (m1.A_2 == m2.A_2) & (m1.A_3 == m2.A_3)

        x = [1., 2., 3.]
        x1, x2, x3 = partition(m1, x)
        @test (x1 == [1.]) & (x2 == [2.]) & (x3 == [3.])

        y = combine(m1, x1, x2, x3)
        @test y == x
    end

    @testset "Basics" begin
        m = PartitionMask(3, [1], [2])
        cl1 = Coupling(x -> Shift(x[1]), m)

        x = [1., 2., 3.]
        @test cl1(x) == [3., 2., 3.]

        cl2 = Coupling(θ -> Shift(θ[1]), m)
        @test cl2(x) == cl1(x)

        # inversion
        icl1 = inv(cl1)
        @test icl1(cl1(x)) == x
        @test inv(cl2)(cl2(x)) == x

        # This `cl2` should result in
        b = Shift(x[2:2])

        # logabsdetjac
        @test logabsdetjac(cl1, x) == logabsdetjac(b, x[1:1])

        # forward
        @test forward(cl1, x) == (rv = cl1(x), logabsdetjac = logabsdetjac(cl1, x))
        @test forward(icl1, cl1(x)) == (rv = x, logabsdetjac = - logabsdetjac(cl1, x))
    end

    @testset "Tracker" begin
        Random.seed!(123)
        x = [1., 2., 3.]

        m = PartitionMask(length(x), [1], [2])
        nn = Flux.Chain(Flux.Dense(1, 2, Flux.sigmoid), Flux.Dense(2, 1))
        nn_tracked = Flux.fmap(x -> (x isa AbstractArray) ? Tracker.param(x) : x, nn)
        cl = Coupling(θ -> Shift(nn_tracked(θ)), m)

        # should leave two last indices unchanged
        @test cl(x)[2:3] == x[2:3]

        # verify that indeed it's tracked
        @test Tracker.istracked(cl(x))
    end
end
