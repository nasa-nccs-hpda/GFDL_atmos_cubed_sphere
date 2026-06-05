#ifndef HELD_SUAREZ_CONFIG_HPP
#define HELD_SUAREZ_CONFIG_HPP

// ============================================================================
// Held-Suarez Forcing Module: Configuration
//
// This header defines physical constants, configuration structures, and
// enumeration types for the Held-Suarez forcing module.
//
// Design principles:
//   - All parameters explicit (no hidden module state)
//   - Fortran variable names preserved where useful
//   - Compatible with iso_c_binding (POD types, no std::string in config)
//   - Double precision throughout (matches Fortran -fdefault-real-8)
// ============================================================================

namespace hs_forcing {

// ============================================================================
// Physical Constants
//
// Values match FMS constants_mod. Inlined here to avoid FMS dependency.
// ============================================================================

namespace constants {
    constexpr double KAPPA = 2.0 / 7.0;              // R/cp for dry air
    constexpr double CP_AIR = 1004.0;               // J/(kg*K)
    constexpr double GRAV = 9.80665;                // m/s^2
    constexpr double PI = 3.14159265358979323846;
    constexpr double SECONDS_PER_DAY = 86400.0;
    constexpr double STEFAN = 5.670374419e-8;       // W/(m^2*K^4)
}

// ============================================================================
// Enumeration Types
// ============================================================================

// Equilibrium temperature calculation method
// Maps to Fortran: equilibrium_t_option
enum EquilibriumOption {
    EQUILIBRIUM_HELD_SUAREZ = 0,   // Standard Held-Suarez (1994)
    EQUILIBRIUM_TOP_DOWN = 1       // Tropopause-aware top-down model
    // EQUILIBRIUM_FROM_FILE = 2   // Deferred: requires interpolator
    // EQUILIBRIUM_EXOPLANET = 3   // Deferred: requires astronomy_mod
};

// Stratosphere temperature handling (top_down mode only)
// Maps to Fortran: stratosphere_t_option
enum StratosphereOption {
    STRATOSPHERE_DEFAULT = 0,      // Cap at 0 K (effectively no cap)
    STRATOSPHERE_C_ABOVE_TP = 1,   // Constant tstr above tropopause
    STRATOSPHERE_HS_LIKE = 2,      // max(teq, tstr) like standard HS
    STRATOSPHERE_EXTEND_TP = 3     // Extend tropopause temperature
};

// ============================================================================
// Configuration Structure
//
// Contains all namelist parameters from hs_forcing_nml.
// Designed for:
//   - Direct initialization from Fortran via iso_c_binding
//   - Self-contained (no pointers to external data)
//   - POD-like (trivially copyable)
// ============================================================================

struct Config {
    // ========================================================================
    // Equilibrium Temperature Parameters
    // ========================================================================

    double t_zero;      // Equatorial equilibrium temperature [K]
                        // Fortran default: 315.0

    double t_strat;     // Stratospheric temperature minimum [K]
                        // Fortran default: 200.0

    double delh;        // Equator-pole temperature difference [K]
                        // Fortran default: 60.0

    double delv;        // Static stability parameter [K]
                        // Fortran default: 10.0

    double eps;         // Hemispheric asymmetry [K]
                        // Fortran default: 0.0

    double P00;         // Reference pressure [Pa]
                        // Fortran default: 1.0e5

    double kappa;       // R/cp ratio
                        // Fortran default: 2/7 (from constants_mod)

    // ========================================================================
    // Damping Timescale Parameters
    //
    // These are in units of [1/s]. The Fortran namelist uses days (negative
    // values indicate days), but these are pre-converted.
    // ========================================================================

    double tka;         // Atmospheric relaxation rate [1/s]
                        // Derived from ka_days: tka = 1/(86400*|ka|)
                        // Default ka = -40 days -> tka ~ 2.894e-7

    double tks;         // Surface relaxation rate [1/s]
                        // Derived from ks_days: tks = 1/(86400*|ks|)
                        // Default ks = -4 days -> tks ~ 2.894e-6

    double vkf;         // Rayleigh friction rate [1/s]
                        // Derived from kf_days: vkf = 1/(86400*|kf|)
                        // Default kf = -1 day -> vkf ~ 1.157e-5

    double sigma_b;     // Boundary layer top sigma level [dimensionless]
                        // Fortran default: 0.7

    // ========================================================================
    // Orbital Parameters (used by top_down mode)
    // ========================================================================

    double orbital_period;  // Orbital period [days]
                            // Fortran default: 365.25 (from constants_mod)

    double ecc;             // Orbital eccentricity [dimensionless]
                            // Fortran default: 0.0167 (from astronomy_mod)

    double obliq;           // Obliquity [degrees]
                            // Fortran default: 23.44 (from astronomy_mod)

    double peri_time;       // Perihelion time as fraction of orbital period
                            // Fortran default: 0.25

    double smaxis;          // Semi-major axis [m]
                            // Fortran default: 1.496e11

    // ========================================================================
    // Radiative Parameters (used by top_down mode)
    // ========================================================================

    double solar_const;     // Solar constant [W/m^2]
                            // Fortran default: 1360.0 (from constants_mod)

    double stefan;          // Stefan-Boltzmann constant [W/(m^2*K^4)]
                            // Fortran default: 5.67e-8 (from constants_mod)

    double albedo;          // Surface albedo [dimensionless]
                            // Fortran default: 0.3

    // ========================================================================
    // Tropopause/Heat Capacity Parameters (used by top_down mode)
    // ========================================================================

    double lapse;           // Lapse rate [K/km]
                            // Fortran default: 6.5

    double h_a;             // Atmospheric scale height parameter
                            // Fortran default: 2.0

    double tau_s;           // Optical depth parameter
                            // Fortran default: 5.0

    double heat_capacity;   // Heat capacity [J/(m^3*K)]
                            // Fortran default: 4.2e6

    double ml_depth;        // Mixed layer depth [m]
                            // Fortran default: 1.0

    // ========================================================================
    // Control Flags
    // ========================================================================

    int do_conserve_energy; // Apply energy conservation term (0=false, 1=true)
                            // Fortran default: .true.

    int equilibrium_option; // EquilibriumOption enum value
                            // Fortran default: 'Held_Suarez' -> 0

    int stratosphere_option;// StratosphereOption enum value (top_down only)
                            // Fortran default: 'hs_like' -> 2

    // ========================================================================
    // Methods
    // ========================================================================

    // Set all parameters to Fortran defaults
    void set_defaults() {
        // Equilibrium temperature
        t_zero = 315.0;
        t_strat = 200.0;
        delh = 60.0;
        delv = 10.0;
        eps = 0.0;
        P00 = 1.0e5;
        kappa = constants::KAPPA;

        // Damping timescales (pre-converted from days)
        // ka = -40 days, ks = -4 days, kf = -1 day
        tka = 1.0 / (constants::SECONDS_PER_DAY * 40.0);
        tks = 1.0 / (constants::SECONDS_PER_DAY * 4.0);
        vkf = 1.0 / (constants::SECONDS_PER_DAY * 1.0);
        sigma_b = 0.7;

        // Orbital parameters
        orbital_period = 365.25;
        ecc = 0.0167;
        obliq = 23.44;
        peri_time = 0.25;
        smaxis = 1.496e11;

        // Radiative parameters
        solar_const = 1360.0;
        stefan = constants::STEFAN;
        albedo = 0.3;

        // Tropopause/heat capacity
        lapse = 6.5;
        h_a = 2.0;
        tau_s = 5.0;
        heat_capacity = 4.2e6;
        ml_depth = 1.0;

        // Control flags
        do_conserve_energy = 1;
        equilibrium_option = EQUILIBRIUM_HELD_SUAREZ;
        stratosphere_option = STRATOSPHERE_HS_LIKE;
    }

    // Convert damping timescales from days to 1/s
    // Call this if setting ka_days, ks_days, kf_days directly
    void convert_timescales(double ka_days, double ks_days, double kf_days) {
        tka = 1.0 / (constants::SECONDS_PER_DAY * (ka_days > 0 ? ka_days : -ka_days));
        tks = 1.0 / (constants::SECONDS_PER_DAY * (ks_days > 0 ? ks_days : -ks_days));
        vkf = 1.0 / (constants::SECONDS_PER_DAY * (kf_days > 0 ? kf_days : -kf_days));
    }

    // Factory method for default configuration
    static Config defaults() {
        Config cfg;
        cfg.set_defaults();
        return cfg;
    }
};

// ============================================================================
// Array Indexing Helpers
//
// Fortran uses column-major order: arr(i,j,k) is stored as
//   arr(1,1,1), arr(2,1,1), ..., arr(nlon,1,1), arr(1,2,1), ...
//
// C++ must use the same layout for compatibility with Fortran arrays
// passed via iso_c_binding.
// ============================================================================

// 2D array index: arr[i + nlon * j] for arr(i,j) in Fortran
inline int idx2(int i, int j, int nlon) {
    return i + nlon * j;
}

// 3D array index: arr[i + nlon * (j + nlat * k)] for arr(i,j,k) in Fortran
inline int idx3(int i, int j, int k, int nlon, int nlat) {
    return i + nlon * (j + nlat * k);
}

// 4D array index: arr[i + nlon * (j + nlat * (k + nlev * n))] for arr(i,j,k,n)
inline int idx4(int i, int j, int k, int n, int nlon, int nlat, int nlev) {
    return i + nlon * (j + nlat * (k + nlev * n));
}

} // namespace hs_forcing

#endif // HELD_SUAREZ_CONFIG_HPP
