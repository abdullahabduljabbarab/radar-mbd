function [y, w] = mvdr_beamform(rx, x_elements, lambda, theta_look_rad, load_factor)
%MVDR_BEAMFORM  Minimum Variance Distortionless Response beamforming.
%
%   [Y, W] = MVDR_BEAMFORM(RX, X_ELEMENTS, LAMBDA, THETA_LOOK_RAD, LOAD_FACTOR)
%   applies MVDR (Capon) adaptive beamforming to an N_snapshots x N_elements
%   complex array signal RX. Returns Y as the N_snapshots x 1 beamformed
%   output and W as the N_elements x 1 complex weight vector applied.
%
%   MVDR minimises output power subject to a distortionless-response
%   constraint at the look direction. Closed-form weights:
%
%       R_hat = (1/K) * RX' * RX             sample spatial covariance
%       R_hat = R_hat + load_factor * trace(R_hat)/N * I   diagonal loading
%       a     = steering_vector(theta_look)
%       w     = R_hat^{-1} a  /  (a^H R_hat^{-1} a)
%       y[k]  = w^H * RX[k, :]^T
%
%   Diagonal loading regularises the inverse when K is small compared
%   to N (snapshot-deficient regime). Load factor is a fraction of the
%   trace of R_hat divided by N so the loading matches the noise scale.
%
%   Output y is single-channel complex data at the look direction.
%   Any point signal from an angle other than THETA_LOOK is attenuated
%   according to how far it sits from the mainlobe; strong jammers get
%   an adaptive null placed on them. Feeds directly into the matched
%   filter downstream.
%
%   Codegen-safe: uses only matrix multiply, transpose, inverse
%   (mldivide), and complex arithmetic. All arrays are fixed size at
%   compile time (N_snapshots x N_elements in, N_snapshots x 1 out).
%   - TripleA

    [K, N] = size(rx);

    % ---- Sample spatial covariance matrix R = <x x^H> ----
    % For MATLAB storage where each ROW of rx is a snapshot x^T:
    %   R(i,j) = <x_i * conj(x_j)> = mean_k rx(k,i) * conj(rx(k,j))
    % Which in matrix form is (rx.' * conj(rx)) / K. Using rx' * rx
    % would give the CONJUGATE covariance (transposed indices), and
    % the MVDR inverse would then act on the wrong eigenvectors and
    % fail to null strong sources. - TripleA
    R_hat = (rx.' * conj(rx)) / K;               % N x N

    % ---- Diagonal loading for numerical stability ----
    R_load = R_hat + load_factor * (trace(R_hat) / N) * eye(N);

    % ---- Steering vector at look direction ----
    a = steering_vector(theta_look_rad, x_elements, lambda);

    % ---- MVDR weights (closed form) ----
    Rinv_a = R_load \ a;                         % solve R_load * x = a
    w = Rinv_a / (a' * Rinv_a);                  % N x 1

    % ---- Apply weights ----
    y = rx * conj(w);                            % K x 1  (equivalent to w' * rx')
end
