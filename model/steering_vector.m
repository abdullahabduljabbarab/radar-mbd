function a = steering_vector(theta_rad, x_elements, lambda)
%STEERING_VECTOR  Plane-wave steering vector for a linear array.
%
%   A = STEERING_VECTOR(THETA_RAD, X_ELEMENTS, LAMBDA) returns the
%   complex steering vector A (length N) for a plane wave arriving
%   from angle THETA_RAD (radians, measured from array broadside)
%   at a uniform linear array with element positions X_ELEMENTS
%   (metres, length N) at wavelength LAMBDA (metres).
%
%   Convention: theta = 0 is broadside (perpendicular to the array
%   axis), positive theta is toward the +x end. Element i sees the
%   plane wave with time-of-arrival advance proportional to
%   x_i * sin(theta) / c, i.e. phase advance
%       phi_i = 2*pi * x_i * sin(theta) / lambda.
%   The steering vector is the phase pattern the array would need
%   to apply on transmit to point the beam at theta, or equivalently
%   the phase pattern received across the array from a plane wave
%   arriving from theta.
%
%   Codegen-safe: only real arithmetic + complex exponentials, no
%   dynamic allocation. Standard N-element geometry. - TripleA

    a = exp(1j * 2*pi * x_elements(:) * sin(theta_rad) / lambda);
end
