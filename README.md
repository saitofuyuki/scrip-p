# SCRIP
SCRIP is a software package which computes addresses and weights for remapping and interpolating fields between grids in 
spherical coordinates. It was written originally for remapping fields to other grids in a coupled climate model, but is 
sufficiently general that it can be used in other applications as well. The package should work for any grid on the surface 
of a sphere. SCRIP currently supports five remapping options:

* Conservative remapping: First- and second-order conservative remapping as described in Jones (1999, Monthly Weather Review, 127, 2204-2210).
* Bilinear interpolation: Slightly generalized to use a local bilinear approximation (only logically-rectangular grids).
* Bicubic interpolation: Similarly generalized (only logically-rectangular grids).
* Distance-weighted averaging: Inverse-distance-weighted average of a user-specified number of nearest neighbor values.
* Particle remapping: A conservative particle (Monte-Carlo-like) remapping scheme

# SCRIP-p
SCRIP-p (p is for pivot) is a fork of SCRIP version 1.5.
A fundamental problem relating to the treatment of centroid in the
second-order conservative remapping method is fixed in three methods.
In order to simplify the modification, individual branch is created
for each method.
Details are described in Saito (2024, GMDD), which is still under
discussion including the problem itself.

It is expected to work correctly, however, neither the copyright
holder nor the maintainer of the modification part makes any warranty,
express or implied, or assumes any liability or responsibility for the
use of this software.

## scheme-P - pivot scheme
Most compatible scheme with the original.
Additional weights are introduced, i.e., `num_wgts` = 4.
Accordingly `remap_matrix` has one more column to holds the additional
weight.  This weights are indeed a temporal variable to compute the
pivot longitudes concurrently with the other weights, and not
necessary at the remapping stage.  It is better to exclude from the
remapping table, but at the moment is kept for simplicity.

## fix/scheme-Cd - centroid-derivative scheme
Most simple scheme.  Pivot is replaced with centroid (geometric
center).  It requires to modify the caller side to input derivative of
flux, not gradient.  `scrip_test.f` is adjusted to this requirement.

## fix/scheme-Cg - centroid-gradient scheme
A minor variation of scheme-Cd.  Pivot is replaced with centroid, but
adjustment from gradient to derivative is performed at the library
side.
