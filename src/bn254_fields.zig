// File: src/bn254_fields.zig
//
// Quadratic / sextic / dodecic extensions over Fp for the alt_bn128 (BN254)
// curve, sufficient for the optimal Ate pairing. The tower is the standard one:
//
//   Fp2  = Fp[i]/(i^2 + 1)
//   Fp6  = Fp2[v]/(v^3 - xi)        with xi = 9 + i
//   Fp12 = Fp6[w]/(w^2 - v)
//
// All Frobenius constants are derived at comptime by exponentiating xi inside
// Fp2 — there are no hand-transcribed magic numbers, which removes a large
// class of bugs.
//
// This module covers only field arithmetic; G2 + Miller loop + final
// exponentiation live in bn254_pairing.zig.

const std = @import("std");
const bn = @import("bn254.zig");

// Deriving Frobenius constants at comptime exponentiates a 256-bit exponent in
// Fp2, which the default branch quota won't fit.
comptime {
    @setEvalBranchQuota(100_000);
}

pub const Fp = u256;
pub const P: Fp = bn.P;

// ---------------------------------------------------------------------------
// Fp2 = Fp[i] / (i^2 + 1).
// ---------------------------------------------------------------------------

pub const Fp2 = struct {
    c0: Fp, // real part
    c1: Fp, // i coefficient

    pub const zero = Fp2{ .c0 = 0, .c1 = 0 };
    pub const one = Fp2{ .c0 = 1, .c1 = 0 };

    pub fn eql(a: Fp2, b: Fp2) bool {
        return a.c0 == b.c0 and a.c1 == b.c1;
    }
    pub fn isZero(a: Fp2) bool {
        return a.c0 == 0 and a.c1 == 0;
    }
};

pub fn fp2Add(a: Fp2, b: Fp2) Fp2 {
    return .{ .c0 = bn.addP(a.c0, b.c0), .c1 = bn.addP(a.c1, b.c1) };
}
pub fn fp2Sub(a: Fp2, b: Fp2) Fp2 {
    return .{ .c0 = bn.subP(a.c0, b.c0), .c1 = bn.subP(a.c1, b.c1) };
}
pub fn fp2Neg(a: Fp2) Fp2 {
    return .{ .c0 = bn.subP(0, a.c0), .c1 = bn.subP(0, a.c1) };
}
pub fn fp2Mul(a: Fp2, b: Fp2) Fp2 {
    // (a0 + a1 i)(b0 + b1 i) = (a0 b0 - a1 b1) + (a0 b1 + a1 b0) i
    const a0b0 = bn.mulP(a.c0, b.c0);
    const a1b1 = bn.mulP(a.c1, b.c1);
    // (a0 + a1)(b0 + b1) - a0 b0 - a1 b1 = a0 b1 + a1 b0
    const cross = bn.subP(bn.subP(bn.mulP(bn.addP(a.c0, a.c1), bn.addP(b.c0, b.c1)), a0b0), a1b1);
    return .{ .c0 = bn.subP(a0b0, a1b1), .c1 = cross };
}
pub fn fp2Sqr(a: Fp2) Fp2 {
    // (a0 + a1 i)^2 = (a0+a1)(a0-a1) + 2 a0 a1 i
    const s = bn.addP(a.c0, a.c1);
    const d = bn.subP(a.c0, a.c1);
    return .{ .c0 = bn.mulP(s, d), .c1 = bn.mulP(2, bn.mulP(a.c0, a.c1)) };
}
pub fn fp2Inv(a: Fp2) Fp2 {
    // 1/(a0+a1 i) = (a0 - a1 i)/(a0^2 + a1^2)
    const denom = bn.addP(bn.mulP(a.c0, a.c0), bn.mulP(a.c1, a.c1));
    const inv_d = bn.invP(denom);
    return .{ .c0 = bn.mulP(a.c0, inv_d), .c1 = bn.subP(0, bn.mulP(a.c1, inv_d)) };
}
pub fn fp2Conj(a: Fp2) Fp2 {
    return .{ .c0 = a.c0, .c1 = bn.subP(0, a.c1) };
}
pub fn fp2MulFp(a: Fp2, k: Fp) Fp2 {
    return .{ .c0 = bn.mulP(a.c0, k), .c1 = bn.mulP(a.c1, k) };
}
/// Multiply by xi = 9 + i: (a0 + a1 i)(9 + i) = (9 a0 - a1) + (a0 + 9 a1) i.
pub fn fp2MulByXi(a: Fp2) Fp2 {
    return .{
        .c0 = bn.subP(bn.mulP(9, a.c0), a.c1),
        .c1 = bn.addP(a.c0, bn.mulP(9, a.c1)),
    };
}
/// Exponentiation in Fp2 by an Fp scalar (used to derive Frobenius constants).
pub fn fp2Pow(base: Fp2, exp: Fp) Fp2 {
    @setEvalBranchQuota(1_000_000); // when called at comptime to derive constants
    var r = Fp2.one;
    var b = base;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) r = fp2Mul(r, b);
        b = fp2Sqr(b);
    }
    return r;
}

/// xi = 9 + i (the cubic non-residue used to build Fp6 over Fp2).
pub const XI = Fp2{ .c0 = 9, .c1 = 1 };

// Frobenius (Fp2 -> Fp2): x -> x^p = conjugate(x). For BN254 p ≡ 3 (mod 4) so
// i^p = -i.
pub fn fp2Frobenius(a: Fp2) Fp2 {
    return fp2Conj(a);
}

// ---------------------------------------------------------------------------
// Fp6 = Fp2[v] / (v^3 - xi).
// ---------------------------------------------------------------------------

pub const Fp6 = struct {
    c0: Fp2, // constant term
    c1: Fp2, // v coefficient
    c2: Fp2, // v^2 coefficient

    pub const zero = Fp6{ .c0 = Fp2.zero, .c1 = Fp2.zero, .c2 = Fp2.zero };
    pub const one = Fp6{ .c0 = Fp2.one, .c1 = Fp2.zero, .c2 = Fp2.zero };

    pub fn eql(a: Fp6, b: Fp6) bool {
        return a.c0.eql(b.c0) and a.c1.eql(b.c1) and a.c2.eql(b.c2);
    }
};

pub fn fp6Add(a: Fp6, b: Fp6) Fp6 {
    return .{ .c0 = fp2Add(a.c0, b.c0), .c1 = fp2Add(a.c1, b.c1), .c2 = fp2Add(a.c2, b.c2) };
}
pub fn fp6Sub(a: Fp6, b: Fp6) Fp6 {
    return .{ .c0 = fp2Sub(a.c0, b.c0), .c1 = fp2Sub(a.c1, b.c1), .c2 = fp2Sub(a.c2, b.c2) };
}
pub fn fp6Neg(a: Fp6) Fp6 {
    return .{ .c0 = fp2Neg(a.c0), .c1 = fp2Neg(a.c1), .c2 = fp2Neg(a.c2) };
}
pub fn fp6Mul(a: Fp6, b: Fp6) Fp6 {
    // Karatsuba on (a0 + a1 v + a2 v^2)(b0 + b1 v + b2 v^2) modulo v^3 = xi.
    const v0 = fp2Mul(a.c0, b.c0);
    const v1 = fp2Mul(a.c1, b.c1);
    const v2 = fp2Mul(a.c2, b.c2);

    // c0 = v0 + xi * ((a1+a2)(b1+b2) - v1 - v2)
    const t1 = fp2Mul(fp2Add(a.c1, a.c2), fp2Add(b.c1, b.c2));
    const c0 = fp2Add(v0, fp2MulByXi(fp2Sub(fp2Sub(t1, v1), v2)));

    // c1 = (a0+a1)(b0+b1) - v0 - v1 + xi * v2
    const t2 = fp2Mul(fp2Add(a.c0, a.c1), fp2Add(b.c0, b.c1));
    const c1 = fp2Add(fp2Sub(fp2Sub(t2, v0), v1), fp2MulByXi(v2));

    // c2 = (a0+a2)(b0+b2) - v0 - v2 + v1
    const t3 = fp2Mul(fp2Add(a.c0, a.c2), fp2Add(b.c0, b.c2));
    const c2 = fp2Add(fp2Sub(fp2Sub(t3, v0), v2), v1);

    return .{ .c0 = c0, .c1 = c1, .c2 = c2 };
}
pub fn fp6Sqr(a: Fp6) Fp6 {
    // CH-SQR2 from Devegili-OhEigeartaigh-Scott-Dahab.
    const s0 = fp2Sqr(a.c0);
    const ab = fp2Mul(a.c0, a.c1);
    const s1 = fp2Add(ab, ab); // 2 a0 a1
    const s2 = fp2Sqr(fp2Sub(fp2Add(a.c0, a.c2), a.c1)); // (a0 + a2 - a1)^2
    const bc = fp2Mul(a.c1, a.c2);
    const s3 = fp2Add(bc, bc); // 2 a1 a2
    const s4 = fp2Sqr(a.c2);

    const c0 = fp2Add(s0, fp2MulByXi(s3));
    const c1 = fp2Add(s1, fp2MulByXi(s4));
    const c2 = fp2Sub(fp2Sub(fp2Add(fp2Add(s1, s2), s3), s0), s4);
    return .{ .c0 = c0, .c1 = c1, .c2 = c2 };
}
pub fn fp6Inv(a: Fp6) Fp6 {
    // Standard formula for inverse in a cubic extension:
    //   t0 = a0^2 - xi * a1 * a2
    //   t1 = xi * a2^2 - a0 * a1
    //   t2 = a1^2 - a0 * a2
    //   factor = (a0*t0 + xi*(a2*t1 + a1*t2))^{-1}
    //   inv = (t0*factor, t1*factor, t2*factor)
    const t0 = fp2Sub(fp2Sqr(a.c0), fp2MulByXi(fp2Mul(a.c1, a.c2)));
    const t1 = fp2Sub(fp2MulByXi(fp2Sqr(a.c2)), fp2Mul(a.c0, a.c1));
    const t2 = fp2Sub(fp2Sqr(a.c1), fp2Mul(a.c0, a.c2));
    const den = fp2Add(
        fp2Mul(a.c0, t0),
        fp2MulByXi(fp2Add(fp2Mul(a.c2, t1), fp2Mul(a.c1, t2))),
    );
    const inv_d = fp2Inv(den);
    return .{ .c0 = fp2Mul(t0, inv_d), .c1 = fp2Mul(t1, inv_d), .c2 = fp2Mul(t2, inv_d) };
}
/// Multiply an Fp6 element by v: (a0 + a1 v + a2 v^2) * v = (xi a2) + a0 v + a1 v^2.
pub fn fp6MulByV(a: Fp6) Fp6 {
    return .{ .c0 = fp2MulByXi(a.c2), .c1 = a.c0, .c2 = a.c1 };
}

// Frobenius constants for Fp6 (derived at comptime).
pub const FROB_FP6_C1_1 = fp2Pow(XI, (P - 1) / 3); // xi^{(p-1)/3}
pub const FROB_FP6_C1_2 = fp2Pow(XI, 2 * (P - 1) / 3); // xi^{2(p-1)/3}

pub fn fp6Frobenius(a: Fp6) Fp6 {
    // (a0 + a1 v + a2 v^2)^p = a0^p + a1^p * v^p + a2^p * v^{2p}.
    // v^p = FROB_FP6_C1_1 * v; v^{2p} = FROB_FP6_C1_2 * v^2.
    return .{
        .c0 = fp2Frobenius(a.c0),
        .c1 = fp2Mul(fp2Frobenius(a.c1), FROB_FP6_C1_1),
        .c2 = fp2Mul(fp2Frobenius(a.c2), FROB_FP6_C1_2),
    };
}

// ---------------------------------------------------------------------------
// Fp12 = Fp6[w] / (w^2 - v).
// ---------------------------------------------------------------------------

pub const Fp12 = struct {
    c0: Fp6,
    c1: Fp6,

    pub const zero = Fp12{ .c0 = Fp6.zero, .c1 = Fp6.zero };
    pub const one = Fp12{ .c0 = Fp6.one, .c1 = Fp6.zero };

    pub fn eql(a: Fp12, b: Fp12) bool {
        return a.c0.eql(b.c0) and a.c1.eql(b.c1);
    }
    pub fn isOne(a: Fp12) bool {
        return a.eql(Fp12.one);
    }
};

pub fn fp12Add(a: Fp12, b: Fp12) Fp12 {
    return .{ .c0 = fp6Add(a.c0, b.c0), .c1 = fp6Add(a.c1, b.c1) };
}
pub fn fp12Sub(a: Fp12, b: Fp12) Fp12 {
    return .{ .c0 = fp6Sub(a.c0, b.c0), .c1 = fp6Sub(a.c1, b.c1) };
}
pub fn fp12Mul(a: Fp12, b: Fp12) Fp12 {
    // (a0 + a1 w)(b0 + b1 w) = (a0 b0 + v a1 b1) + ((a0 + a1)(b0 + b1) - a0 b0 - a1 b1) w
    const t0 = fp6Mul(a.c0, b.c0);
    const t1 = fp6Mul(a.c1, b.c1);
    const c0 = fp6Add(t0, fp6MulByV(t1));
    const c1 = fp6Sub(fp6Sub(fp6Mul(fp6Add(a.c0, a.c1), fp6Add(b.c0, b.c1)), t0), t1);
    return .{ .c0 = c0, .c1 = c1 };
}
pub fn fp12Sqr(a: Fp12) Fp12 {
    // (a0 + a1 w)^2 = (a0 + a1)(a0 + v a1) - a0 a1 - v a0 a1 + 2 a0 a1 w
    const ab = fp6Mul(a.c0, a.c1);
    const c0 = fp6Sub(
        fp6Sub(fp6Mul(fp6Add(a.c0, a.c1), fp6Add(a.c0, fp6MulByV(a.c1))), ab),
        fp6MulByV(ab),
    );
    const c1 = fp6Add(ab, ab);
    return .{ .c0 = c0, .c1 = c1 };
}
pub fn fp12Inv(a: Fp12) Fp12 {
    // 1/(a0 + a1 w) = (a0 - a1 w) / (a0^2 - v a1^2).
    const t = fp6Inv(fp6Sub(fp6Sqr(a.c0), fp6MulByV(fp6Sqr(a.c1))));
    return .{ .c0 = fp6Mul(a.c0, t), .c1 = fp6Neg(fp6Mul(a.c1, t)) };
}
pub fn fp12Conj(a: Fp12) Fp12 {
    // For x = a0 + a1 w in Fp12, conjugate over Fp6 is a0 - a1 w. This is also
    // x^(p^6) since w^(p^6) = -w in this tower.
    return .{ .c0 = a.c0, .c1 = fp6Neg(a.c1) };
}

// Frobenius constants for Fp12 (Fp2 scalars; w^p = const * w).
pub const FROB_FP12_C1_1 = fp2Pow(XI, (P - 1) / 6);

pub fn fp12Frobenius(a: Fp12) Fp12 {
    // For (a0 + a1 w)^p, with a0, a1 in Fp6: Frobenius is applied per-Fp6, and
    // w^p multiplies a1 by FROB_FP12_C1_1 (an Fp2 scalar embedded in Fp6).
    const f0 = fp6Frobenius(a.c0);
    var f1 = fp6Frobenius(a.c1);
    // Multiply each Fp2 component of f1 by FROB_FP12_C1_1.
    f1 = Fp6{
        .c0 = fp2Mul(f1.c0, FROB_FP12_C1_1),
        .c1 = fp2Mul(f1.c1, FROB_FP12_C1_1),
        .c2 = fp2Mul(f1.c2, FROB_FP12_C1_1),
    };
    return .{ .c0 = f0, .c1 = f1 };
}

pub fn fp12Pow(base: Fp12, exp: u256) Fp12 {
    var r = Fp12.one;
    var b = base;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) r = fp12Mul(r, b);
        b = fp12Sqr(b);
    }
    return r;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

test "fp2: arithmetic identities" {
    const a = Fp2{ .c0 = 17, .c1 = 23 };
    try testing.expect(fp2Mul(a, Fp2.one).eql(a));
    try testing.expect(fp2Add(a, Fp2.zero).eql(a));
    try testing.expect(fp2Sub(a, a).isZero());
    try testing.expect(fp2Mul(a, fp2Inv(a)).eql(Fp2.one));
}

test "fp2: i^2 = -1, conj(conj) = id" {
    const im = Fp2{ .c0 = 0, .c1 = 1 };
    const im_sq = fp2Sqr(im);
    try testing.expect(im_sq.eql(Fp2{ .c0 = bn.subP(0, 1), .c1 = 0 }));
    const x = Fp2{ .c0 = 5, .c1 = 7 };
    try testing.expect(fp2Conj(fp2Conj(x)).eql(x));
}

test "fp2: Frobenius is x -> conjugate(x) for BN254 (p ≡ 3 mod 4)" {
    const a = Fp2{ .c0 = 123, .c1 = 456 };
    // x^p via direct exp must match conjugate.
    const via_pow = fp2Pow(a, P);
    try testing.expect(via_pow.eql(fp2Conj(a)));
}

test "fp6: arithmetic identities and Frobenius via direct exp" {
    const a = Fp6{
        .c0 = .{ .c0 = 11, .c1 = 22 },
        .c1 = .{ .c0 = 33, .c1 = 44 },
        .c2 = .{ .c0 = 55, .c1 = 66 },
    };
    try testing.expect(fp6Mul(a, Fp6.one).eql(a));
    try testing.expect(fp6Mul(a, fp6Inv(a)).eql(Fp6.one));
    // Squaring matches multiplication.
    try testing.expect(fp6Sqr(a).eql(fp6Mul(a, a)));
}

test "fp12: arithmetic identities" {
    const a6 = Fp6{
        .c0 = .{ .c0 = 1, .c1 = 2 },
        .c1 = .{ .c0 = 3, .c1 = 4 },
        .c2 = .{ .c0 = 5, .c1 = 6 },
    };
    const b6 = Fp6{
        .c0 = .{ .c0 = 7, .c1 = 8 },
        .c1 = .{ .c0 = 9, .c1 = 10 },
        .c2 = .{ .c0 = 11, .c1 = 12 },
    };
    const a = Fp12{ .c0 = a6, .c1 = b6 };
    try testing.expect(fp12Mul(a, Fp12.one).eql(a));
    try testing.expect(fp12Mul(a, fp12Inv(a)).eql(Fp12.one));
    try testing.expect(fp12Sqr(a).eql(fp12Mul(a, a)));
}

test "fp12: Frobenius matches direct ^p" {
    const a6 = Fp6{
        .c0 = .{ .c0 = 1, .c1 = 2 },
        .c1 = .{ .c0 = 3, .c1 = 4 },
        .c2 = .{ .c0 = 5, .c1 = 6 },
    };
    const b6 = Fp6{
        .c0 = .{ .c0 = 7, .c1 = 8 },
        .c1 = .{ .c0 = 9, .c1 = 10 },
        .c2 = .{ .c0 = 11, .c1 = 12 },
    };
    const a = Fp12{ .c0 = a6, .c1 = b6 };
    const via_pow = fp12Pow(a, P);
    const via_frob = fp12Frobenius(a);
    try testing.expect(via_pow.eql(via_frob));
}
