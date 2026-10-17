function R = BE_TravelTime(txFile, rxFile, opts)
%BE_TRAVELTIME  Bender-element shear-wave travel-time analysis (ASTM D8295-19).
%
%   R = BE_TravelTime()                    -> asks for the TRANSMITTER file, then
%                                             (separately) for the RECEIVER file
%   R = BE_TravelTime(txFile, rxFile)      -> uses the given paths
%   R = BE_TravelTime(txFile, rxFile, opts)-> with options (see defaultOptions below)
%
%   Input files: oscilloscope CSV exports with a key/value header followed by
%   a "Waveform Data" block (e.g. GW Instek GDS "Fast" mode: one integer ADC
%   count per line; "Detail" mode time,value pairs are also accepted).
%   Both files must come from the SAME acquisition (same trigger, same time
%   base), e.g. CH1 = transmitter, CH2 = receiver.
%
%   Travel-time methods (times are measured from the transmitter):
%     1  Start to Start            ASTM D8295-19 §10.1.2
%     2  Peak to Peak              ASTM D8295-19 §10.1.1
%     3  Trough to Trough          consistency check on the 2nd lobe (not in D8295)
%     4  Cross-correlation         time domain, raw signals shape (D8295 §10.2: "other method")
%     5  Envelope cross-correl.    Hilbert envelopes                (D8295 §10.2)
%     6  Cross-power spectrum      phase slope / group delay        (D8295 §10.2)
%     7  First deflection          near-field onset, informational (lower bound)
%     8  Manual pick (optional)    opts.manualPick = true
%   D8295 §10.2 allows methods other than 1-2 only "provided they have been
%   shown to provide reliable results"; report which method you used (§12.3.11).
%
%   Shear-wave velocity / Gmax (D8295 Eq. 1-3) are computed only if you
%   supply the geometry (opts.H_i, opts.dH_c, opts.H_b, or opts.L directly),
%   the time-delay correction opts.Tc (§8.1) and the density opts.rho.
%
%   Requires: base MATLAB only. The optional Butterworth filter
%   (opts.filterType = 'butter') needs the Signal Processing Toolbox.
%
%   Written for MATLAB R2025b.

% ------------------------------------------------------------------------
if nargin < 3 || isempty(opts), opts = struct(); end
opts = defaultOptions(opts);

% ---- 1. File selection: each file chosen separately ---------------------
filt = {'*.csv;*.CSV;*.txt', 'Oscilloscope export (*.csv, *.txt)'; '*.*', 'All files (*.*)'};
if nargin < 1 || isempty(txFile)
    [f, p] = uigetfile(filt, 'Select the TRANSMITTED signal file (e.g. *_1.CSV)');
    if isequal(f, 0), error('BE:cancelled', 'No transmitter file selected.'); end
    txFile = fullfile(p, f);
end
if nargin < 2 || isempty(rxFile)
    [f, p] = uigetfile(filt, 'Select the RECEIVED signal file (e.g. *_2.CSV)', [fileparts(txFile) filesep]);
    if isequal(f, 0), error('BE:cancelled', 'No receiver file selected.'); end
    rxFile = fullfile(p, f);
end
if strcmpi(txFile, rxFile)
    error('BE:sameFile', 'Transmitter and receiver files are the same file.');
end

% ---- 2. Read both records -----------------------------------------------
TX = readScopeCSV(txFile, opts);
RX = readScopeCSV(rxFile, opts);
checkCompatible(TX, RX);
dt = TX.dt;  fs = 1/dt;
N  = min(numel(TX.v), numel(RX.v));
t  = (0:N-1).' * dt;                 % common time base, s
x  = TX.v(1:N);                      % transmitter, V
yr = RX.v(1:N);                      % receiver (raw), V

% ---- 3. Transmitter: start, peaks, frequency -----------------------------
T = analyseTransmitter(t, x, opts);
x = x - T.baseline;                  % baseline-free transmitter
f0 = T.f.primary;

% ---- 4. Receiver: offset removal and filtering ---------------------------
iPre = t < T.tStart;                 % nothing can arrive before excitation
if nnz(iPre) < 20
    warning('BE:shortPretrigger', ['Fewer than 20 pre-trigger samples; receiver offset ' ...
        'and noise estimates are unreliable. Record more pre-trigger signal (D8295 §9.5).']);
    iPre(1:min(20, N)) = true;
end
yr = yr - mean(yr(iPre));
[y, F] = filterReceiver(yr, fs, f0, opts);
y  = opts.rxPolarity * y;            % D8295 §7.4.1: optional trace inversion
yr = opts.rxPolarity * yr;
F.noiseRaw  = robustStd(yr(iPre));
F.noiseFilt = robustStd(y(iPre));

% ---- 5. Receiver picks ---------------------------------------------------
P = pickReceiver(t, y, yr, T, F, opts);

% ---- 6. Travel times by every method -------------------------------------
M = struct('name', {}, 'tag', {}, 'basis', {}, 'Ts', {}, 'quality', {}, 'note', {});
M(end+1) = mrow('Start to Start',     'S2S', 'ASTM D8295 §10.1.2', P.tArrival - T.tStart, P.ok, ...
               'rx baseline crossing before 1st peak minus tx start');
M(end+1) = mrow('Peak to Peak',       'P2P', 'ASTM D8295 §10.1.1', P.tPeak1 - T.tPeak, P.ok, ...
               '1st rx peak minus 1st tx peak');
M(end+1) = mrow('Trough to Trough',   'T2T', 'check (not in D8295)', P.tTrough1 - T.tTrough, ...
               P.ok && ~isnan(P.tTrough1), '1st rx trough after the 1st peak minus tx trough');
C  = crossCorr(x, y, dt, T, opts, false);
M(end+1) = mrow('Cross-correlation',  'CC', 'D8295 §10.2 (other)', C.lag, C.ok, ...
               sprintf('max normalised CC = %.3f', C.peak));
CE = crossCorr(x, y, dt, T, opts, true);
M(end+1) = mrow('Envelope cross-correlation', 'ECC', 'D8295 §10.2 (other)', CE.lag, CE.ok, ...
               sprintf('max normalised CC of envelopes = %.3f', CE.peak));
S  = crossSpectrum(x, y, fs, f0, F, opts);
M(end+1) = mrow('Cross-power spectrum', 'CPS', 'D8295 §10.2 (other)', S.tau, S.ok, ...
               sprintf('phase-slope fit %.1f-%.1f kHz, R^2 = %.3f', S.band/1e3, S.R2));
M(end+1) = mrow('First deflection',   'FD', 'informational (near-field onset)', ...
               P.tFirstDev - T.tStart, ~isnan(P.tFirstDev), ...
               sprintf('first sustained |rx| > %g x noise; lower bound, includes near field', opts.noiseK));

% ---- 7. Raw-signal cross-correlation as a filter-sensitivity check -------
Craw = crossCorr(x, yr, dt, T, opts, false);

% ---- 8. Figures ----------------------------------------------------------
figs = gobjects(0);
info = figInfo(TX, RX, T, F, opts);
figs(end+1) = plotOverview(t, x, yr, y, T, F, P, info, opts);
figs(end+1) = plotS2S(t, x, yr, y, T, P, M(1), info, opts);
figs(end+1) = plotPeaks(t, x, yr, y, T, P, M(2), M(3), info, opts);
figs(end+1) = plotCC(t, x, y, C,  T, M(4), info, opts, 'Cross-correlation of transmitter and receiver signals');
figs(end+1) = plotCC(t, T.env, P.env, CE, T, M(5), info, opts, 'Cross-correlation of signal envelopes');
figs(end+1) = plotCPS(S, M(6), info);

% ---- 9. Optional manual pick (D8295 Fig. 3 style, user clicks) -----------
if opts.manualPick
    [tsMan, okMan] = manualPick(t, x, y, T, info);
    M(end+1) = mrow('Manual pick', 'MAN', 'user pick', tsMan, okMan, 'clicked tx point then rx point');
end

% ---- 10. Velocity, Gmax, wavelength ratio --------------------------------
M = addVelocity(M, opts, f0, P.fRx);
figs(end+1) = plotSummary(M, Craw, info, opts);

% ---- 11. Report ----------------------------------------------------------
R = struct();
R.files     = struct('tx', txFile, 'rx', rxFile);
R.meta      = struct('tx', TX.meta, 'rx', RX.meta);
R.dt        = dt;
R.transmitter = T;
R.filter    = rmfield(F, {'H', 'fAxis'});
R.picks     = rmfield(P, 'env');
R.cc        = C;  R.ccEnvelope = CE;  R.ccRaw = Craw;  R.crossSpectrum = S;
R.methods   = M;
R.table     = struct2table(rmfield(M, 'tag'));
R.options   = opts;
R.figures   = figs;
printReport(R);
if opts.saveOutputs
    R.outputFolder = saveOutputs(R, figs, opts);
end
end

% =========================================================================
%                              OPTIONS
% =========================================================================
function o = defaultOptions(o)
d.countsPerDiv   = 25;      % ADC counts per vertical division ("Fast" CSV). UNVERIFIED for
                            % your scope model - affects amplitudes only, never travel times.
d.rxPolarity     = +1;      % -1 inverts the receiver trace (D8295 §7.4.1)
d.filterType     = 'fft';   % 'fft' (zero-phase, no toolbox) | 'butter' (filtfilt) | 'none'
d.filterBand     = [];      % [fLow fHigh] Hz; empty -> [0.25 4]*f_tx
d.filterBandFactor = [0.25 4];
d.butterOrder    = 4;       % for 'butter' (applied forward-backward => zero phase)
d.ampFrac        = 0.25;    % rx peak must reach this fraction of max |rx| in the window
d.noiseK         = 4;       % detection threshold, multiples of filtered pre-trigger noise
d.maxTravelTime  = [];      % s; restricts the search window (empty -> whole record)
d.ccSearchMin    = 0;       % s; smallest admissible lag
d.manualPick     = false;   % true -> click picks on a figure afterwards
d.L              = [];      % m, travel length tip-to-tip (overrides H_i, dH_c, H_b)
d.H_i            = [];      % m, initial specimen height       (D8295 Eq. 1)
d.dH_c           = 0;       % m, height change at reading       (D8295 Eq. 1)
d.H_b            = [];      % m, total bender protrusion        (D8295 Eq. 1)
d.Tc             = 0;       % s, time-delay correction           (D8295 §8.1)
d.rho            = [];      % kg/m^3, total density at reading   (D8295 Eq. 2)
d.saveOutputs    = true;
d.outputFolder   = '';      % empty -> folder "BE_results_<rx file name>" next to rx file
d.showFigures    = true;
fn = fieldnames(d);
for k = 1:numel(fn)
    if ~isfield(o, fn{k}) || (isempty(o.(fn{k})) && ~isempty(d.(fn{k})) && ~ischar(d.(fn{k})))
        o.(fn{k}) = d.(fn{k});
    end
end
if ~ismember(o.rxPolarity, [-1 1]), error('BE:opt', 'opts.rxPolarity must be +1 or -1.'); end
end

% =========================================================================
%                              FILE READING
% =========================================================================
function S = readScopeCSV(file, opts)
txt   = fileread(file);
lines = regexp(txt, '\r\n|\n|\r', 'split');
iData = find(startsWith(strtrim(lines), 'Waveform Data', 'IgnoreCase', true), 1);
if isempty(iData)
    error('BE:format', 'No "Waveform Data" line found in %s.', file);
end
meta = struct();
for k = 1:iData-1
    parts = strsplit(lines{k}, ',');
    key = strtrim(parts{1});
    if isempty(key), continue; end
    val = '';
    if numel(parts) >= 2, val = strtrim(parts{2}); end
    num = str2double(val);
    fld = matlab.lang.makeValidName(key);
    if ~isnan(num), meta.(fld) = num; else, meta.(fld) = val; end
end
data = NaN(numel(lines) - iData, 2);  n = 0;
for k = iData+1:numel(lines)
    s = strtrim(lines{k});
    if isempty(s), continue; end
    v = sscanf(strrep(s, ',', ' '), '%f');
    if isempty(v), continue; end
    n = n + 1;
    data(n, 1:min(2, numel(v))) = v(1:min(2, numel(v))).';
end
data = data(1:n, :);
if n < 50, error('BE:format', 'Only %d data points read from %s.', n, file); end

S.file = file;  S.meta = meta;
[~, nm, ex] = fileparts(file);  S.name = [nm ex];
twoCols = all(~isnan(data(:, 2)));
if twoCols                                   % "Detail" export: time, value (V)
    S.mode = 'time,value';
    S.v    = data(:, 2);
    S.dt   = median(diff(data(:, 1)));
    S.counts = [];
else                                         % "Fast" export: ADC counts
    S.mode = 'ADC counts';
    if ~isfield(meta, 'SamplingPeriod')
        error('BE:format', 'No "Sampling Period" in header of %s.', file);
    end
    S.dt = meta.SamplingPeriod;
    S.counts = data(:, 1);
    vs = 1;
    if isfield(meta, 'VerticalScale'), vs = meta.VerticalScale;
    else, warning('BE:noScale', 'No "Vertical Scale" in %s; amplitudes left in ADC counts.', S.name);
    end
    S.v = S.counts * vs / opts.countsPerDiv;
    if isfield(meta, 'VerticalPosition') && meta.VerticalPosition ~= 0
        warning('BE:vpos', ['%s: Vertical Position = %g is not applied. The DC offset is ' ...
            'removed anyway, so travel times are unaffected.'], S.name, meta.VerticalPosition);
    end
end
if isfield(meta, 'MemoryLength') && meta.MemoryLength ~= numel(S.v)
    warning('BE:length', '%s: header says %d points, %d read.', S.name, meta.MemoryLength, numel(S.v));
end
if ~isempty(S.counts) && numel(unique(S.counts)) < 20
    warning('BE:resolution', ['%s uses only %d distinct ADC levels: the trace is coarsely ' ...
        'quantised. Increase the vertical gain on this channel (D8295 §9.6).'], ...
        S.name, numel(unique(S.counts)));
end
end

function checkCompatible(TX, RX)
if abs(TX.dt - RX.dt) > 1e-6 * TX.dt
    error('BE:timebase', 'Sampling periods differ (%g s vs %g s): not one acquisition.', TX.dt, RX.dt);
end
if numel(TX.v) ~= numel(RX.v)
    warning('BE:length', 'Records have different lengths (%d vs %d); the shorter is used.', ...
        numel(TX.v), numel(RX.v));
end
keys = {'HorizontalScale', 'HorizontalPosition', 'TriggerLevel'};
for k = 1:numel(keys)
    if isfield(TX.meta, keys{k}) && isfield(RX.meta, keys{k}) && ...
            isnumeric(TX.meta.(keys{k})) && ~isequal(TX.meta.(keys{k}), RX.meta.(keys{k}))
        warning('BE:timebase', '"%s" differs between files - are they from the same acquisition?', keys{k});
    end
end
if isfield(TX.meta, 'Source') && isfield(RX.meta, 'Source') && strcmp(TX.meta.Source, RX.meta.Source)
    warning('BE:source', 'Both files come from channel %s. Check the file selection.', TX.meta.Source);
end
end

% =========================================================================
%                              TRANSMITTER
% =========================================================================
function T = analyseTransmitter(t, x, opts) %#ok<INUSD>
N   = numel(x);
x0  = x - median(x);
A0  = max(abs(x0));
iBig = find(abs(x0) > 0.2 * A0, 1);
nb   = max(10, iBig - 20);
if nb >= iBig
    error('BE:pretrigger', 'The transmitter pulse starts at the very beginning of the record.');
end
T.baseline = median(x(1:nb));
xb = x - T.baseline;
T.noise = robustStd(xb(1:nb));
s   = sign(xb(iBig));                 % polarity of the first transmitter lobe
T.sign = s;
z   = s * xb;                         % first lobe positive
A   = max(z(iBig:min(N, iBig + round(numel(x)/4))));

% --- lobe boundaries (zero-valued samples, common in quantised records, are skipped)
iPk = iBig;  while iPk < N && z(iPk+1) >= z(iPk), iPk = iPk + 1; end   % top of first lobe
seg  = find(z(1:iPk) <= 0, 1, 'last');  if isempty(seg), seg = 1; end   % last baseline sample
iMid = iPk;  while iMid < N && z(iMid+1) > 0, iMid = iMid + 1; end      % last positive sample
iNeg = iMid + find(z(iMid+1:end) < 0, 1);                               % first negative sample
if isempty(iNeg)
    error('BE:txShape', 'The transmitter has no negative lobe: not a single-period sine pulse.');
end
iEnd = iNeg;  while iEnd < N && z(iEnd+1) < 0, iEnd = iEnd + 1; end     % last negative sample
[~, j] = min(z(iNeg:iEnd));  iTr = iNeg + j - 1;
A2 = -z(iTr);

% --- peak and trough (sub-sample)
[T.tPeak, T.aPeak]     = refineExtremum(t, z, seg+1, iMid, +1);
[T.tTrough, T.aTrough] = refineExtremum(t, z, iNeg, iEnd, -1);
T.aPeak = s * T.aPeak;  T.aTrough = s * T.aTrough;

% --- start, mid and end: straight line through the near-zero part of each flank,
%     extrapolated to the baseline (insensitive to noise and to quantisation steps)
T.tStart = flankRoot(t, z, seg:iPk,                  0.05*A,   0.30*A);
T.tMid   = flankRoot(t, z, iPk:iTr,                 -0.30*A2,  0.30*A);
T.tEnd   = flankRoot(t, z, iTr:min(N, iEnd + 1),    -0.30*A2, -0.05*A2);
T.tStartCrossing = crossTime(t, z, seg);           % plain baseline crossing, for comparison

% --- frequency estimates
T.f.fullPeriod  = 1 / (T.tEnd - T.tStart);        % one complete sine period
T.f.halfPeriod1 = 1 / (2 * (T.tMid - T.tStart));
T.f.halfPeriod2 = 1 / (2 * (T.tEnd - T.tMid));
T.f.peakTrough  = 1 / (2 * (T.tTrough - T.tPeak));
nfft = 2^nextpow2(16 * N);
X = abs(fft(xb, nfft));  fa = (0:nfft-1).' / nfft / (t(2) - t(1));
half = 2:floor(nfft/2);
[~, im] = max(X(half));
T.f.spectralPeak = fa(half(im));                  % NOT the nominal frequency for a 1-cycle burst
T.f.primary = T.f.fullPeriod;
T.f.method  = 'full period (start to end zero crossing)';
T.period = 1 / T.f.primary;

% --- single-period check (D8295 §6.4 asks for a single-period sine pulse)
after = z(min(N, iEnd + 2):end);
T.extraCycles = ~isempty(after) && max(abs(after)) > 0.2 * A;
if T.extraCycles
    warning('BE:txShape', ['The transmitter signal continues after the first period; ' ...
        'frequency and picks use the first period only.']);
end
spread = std([T.f.fullPeriod T.f.halfPeriod1 T.f.halfPeriod2 T.f.peakTrough]) / T.f.primary;
if spread > 0.05
    warning('BE:txShape', 'Transmitter frequency estimates differ by %.0f %%: pulse is not a clean sine.', 100*spread);
end
T.x   = xb;
T.env = envAnalytic(xb);
end

% =========================================================================
%                              RECEIVER
% =========================================================================
function [y, F] = filterReceiver(yr, fs, f0, opts)
F.type = lower(opts.filterType);
if isempty(opts.filterBand), F.band = opts.filterBandFactor * f0; else, F.band = opts.filterBand; end
F.band(2) = min(F.band(2), 0.45 * fs);
N = numel(yr);
nfft = 2^nextpow2(2 * N);
F.fAxis = (0:nfft/2).' * fs / nfft;
switch F.type
    case 'none'
        y = yr;  F.H = ones(size(F.fAxis));
    case 'fft'
        % zero-phase band-pass: flat pass band, raised-cosine roll-offs one octave wide
        f = F.fAxis;  lo = F.band(1);  hi = F.band(2);
        H = ones(size(f));
        H(f <= lo/2) = 0;
        m = f > lo/2 & f < lo;     H(m) = 0.5 - 0.5*cos(pi*(f(m) - lo/2)/(lo/2));
        m = f > hi & f < 2*hi;     H(m) = 0.5 + 0.5*cos(pi*(f(m) - hi)/hi);
        H(f >= 2*hi) = 0;
        Hfull = [H; flipud(H(2:end-1))];
        Y = fft([yr; zeros(nfft - N, 1)]);
        yy = real(ifft(Y .* Hfull));
        y = yy(1:N);  F.H = H;
    case 'butter'
        if ~(exist('butter', 'file') && exist('filtfilt', 'file'))
            error('BE:toolbox', 'opts.filterType = ''butter'' needs the Signal Processing Toolbox.');
        end
        [b, a] = butter(opts.butterOrder, F.band / (fs/2), 'bandpass');
        y = filtfilt(b, a, yr);
        h = freqz(b, a, F.fAxis, fs);  F.H = abs(h).^2;   % forward-backward magnitude
    otherwise
        error('BE:opt', 'Unknown opts.filterType "%s".', opts.filterType);
end
end

function P = pickReceiver(t, y, yRaw, T, F, opts)
N = numel(y);  s = T.sign;  z = s * y;
tMax = t(end);
if ~isempty(opts.maxTravelTime), tMax = min(tMax, T.tStart + opts.maxTravelTime); end
win = find(t >= T.tStart & t <= tMax);
thrNoise = opts.noiseK * F.noiseFilt;
Amax = max(abs(z(win)));
P.ok = Amax > thrNoise;
P.snr = Amax / F.noiseFilt;
if ~P.ok
    warning('BE:noSignal', ['No receiver signal above %g x noise. See D8295 §9.13 ' ...
        '(contact, stiffness, wiring).'], opts.noiseK);
end
thr = max(thrNoise, opts.ampFrac * Amax);

% local extrema of the filtered receiver in the window
d  = diff(z);
iMx = find([false; d(1:end-1) > 0 & d(2:end) <= 0; false]);
iMn = find([false; d(1:end-1) < 0 & d(2:end) >= 0; false]);
iMx = iMx(iMx >= win(1) & iMx <= win(end) & z(iMx) >= thr);
iMn = iMn(iMn >= win(1) & iMn <= win(end));

P.tPeak1 = NaN; P.aPeak1 = NaN; P.tArrival = NaN; P.tArrivalRaw = NaN; P.tTrough1 = NaN; P.aTrough1 = NaN;
P.tNearField = NaN; P.aNearField = NaN; P.tFirstDev = NaN;
if isempty(iMx)
    P.ok = false;
else
    i1 = iMx(1);
    lo = i1;  while lo > 1 && z(lo-1) > 0, lo = lo - 1; end      % first-peak lobe
    hi = i1;  while hi < N && z(hi+1) > 0, hi = hi + 1; end
    [P.tPeak1, a] = refineExtremum(t, z, lo, hi, +1);  P.aPeak1 = s * a;
    % Start to Start: baseline (zero) crossing that opens this lobe (D8295 §10.1.2)
    P.tArrival = crossTime(t, z, lo - 1);
    % same crossing re-estimated on the UNFILTERED trace (line fit over +/-8 % of a period),
    % because a zero-phase filter is non-causal and can move an onset slightly earlier
    w = round(0.08 * T.period / (t(2) - t(1)));
    k0 = round(interp1(t, (1:N).', P.tArrival));
    kk = (max(1, k0 - w):min(N, k0 + w)).';
    pr = polyfit(t(kk) - P.tArrival, s * yRaw(kk), 1);
    P.tArrivalRaw = P.tArrival - pr(2) / pr(1);
    % first trough after the first peak (opposite lobe)
    lo2 = hi + 1;  hi2 = lo2;  while hi2 < N && z(hi2+1) < 0, hi2 = hi2 + 1; end
    if lo2 < N && min(z(lo2:hi2)) < -thrNoise
        [P.tTrough1, a] = refineExtremum(t, z, lo2, hi2, -1);  P.aTrough1 = s * a;
    end
    % near-field excursion: largest opposite-sign extremum between start and arrival
    nf = iMn(iMn < lo & z(iMn) < -thrNoise);
    if ~isempty(nf)
        [~, j] = min(z(nf));  P.tNearField = t(nf(j));  P.aNearField = s * z(nf(j));
    end
end
% first sustained deflection beyond the noise band (near-field onset)
nSus = max(3, round(0.05 * T.period / (t(2) - t(1))));
above = abs(z) > thrNoise;
for k = win(1):win(end) - nSus
    if all(above(k:k+nSus-1)), P.tFirstDev = t(k); break; end
end
% dominant receiver frequency (zero-padded spectrum of the windowed signal)
seg = zeros(N, 1);  seg(win) = y(win);
nfft = 2^nextpow2(16 * N);
Y = abs(fft(seg, nfft));  fa = (0:nfft-1).' / nfft / (t(2) - t(1));
half = 2:floor(nfft/2);  [~, im] = max(Y(half));
P.fRx = fa(half(im));
P.env = envAnalytic(y);
end

% =========================================================================
%                     CROSS-CORRELATION / CROSS-SPECTRUM
% =========================================================================
function C = crossCorr(x, y, dt, T, opts, useEnvelope)
if useEnvelope, a = envAnalytic(x); b = envAnalytic(y); else, a = x; b = y; end
a = a - mean(a);  b = b - mean(b);
N = numel(a);  nfft = 2^nextpow2(2*N);
c = real(ifft(fft(b, nfft) .* conj(fft(a, nfft))));          % c(k) = sum b(n+k) a(n)
c = [c(end-N+2:end); c(1:N)];  lags = (-(N-1):(N-1)).';
c = c / sqrt(sum(a.^2) * sum(b.^2));                          % normalised coefficient
tl = lags * dt;
lagMax = (N-1)*dt;
if ~isempty(opts.maxTravelTime), lagMax = opts.maxTravelTime; end
ok = tl >= opts.ccSearchMin & tl <= lagMax;
idx = find(ok);
[pk, j] = max(c(idx));  k = idx(j);
lag = tl(k);
if k > 1 && k < numel(c)                                      % parabolic refinement
    den = c(k-1) - 2*c(k) + c(k+1);
    if den < 0, lag = lag + 0.5 * (c(k-1) - c(k+1)) / den * dt; end
end
C.lag = lag;  C.peak = pk;  C.c = c;  C.tl = tl;  C.envelope = useEnvelope;
C.ok = pk > 0;
if ~useEnvelope
    % runner-up peak: a second CC peak close in height means the pick is ambiguous
    d = diff(c);  loc = find([false; d(1:end-1) > 0 & d(2:end) <= 0; false] & ok);
    loc(abs(tl(loc) - tl(k)) < 0.5 * T.period) = [];          % ignore ripples on the main peak
    if isempty(loc), C.secondLag = NaN; C.secondPeak = NaN;
    else, [C.secondPeak, j2] = max(c(loc)); C.secondLag = tl(loc(j2));
    end
    if C.secondPeak > 0.8 * pk
        warning('BE:ccAmbiguous', ['Cross-correlation has a second peak at %.1f us that is %.0f %% ' ...
            'of the maximum; the CC pick may be cycle-skipped.'], 1e6*C.secondLag, 100*C.secondPeak/pk);
    end
end
C.tShiftStart = T.tStart + lag;
end

function S = crossSpectrum(x, y, fs, f0, F, opts) %#ok<INUSD>
N = numel(x);  nfft = 2^nextpow2(8*N);
X = fft(x, nfft);  Y = fft(y, nfft);
f = (0:nfft-1).' * fs / nfft;
G = Y .* conj(X);
half = (1:floor(nfft/2)).';
band = [max(0.5*f0, F.band(1)), min(1.5*f0, F.band(2))];
m = half(f(half) >= band(1) & f(half) <= band(2));
m = m(abs(X(m)) >= 0.3 * max(abs(X(half))));                 % keep frequencies the tx excites
S.band = [f(m(1)) f(m(end))];
phAll = unwrap(angle(G(half)));
ph = phAll(m);
w  = abs(G(m));  w = w / max(w);
Aw = [ones(numel(m),1) 2*pi*f(m)] .* sqrt(w);
p  = Aw \ (ph .* sqrt(w));                                    % weighted LS: ph = p1 + p2*2*pi*f
S.tau = -p(2);
res = ph - (p(1) + p(2)*2*pi*f(m));
S.R2 = 1 - sum(w .* res.^2) / sum(w .* (ph - sum(w.*ph)/sum(w)).^2);
S.ok = S.tau > 0 && S.R2 > 0.9;
S.f = f(half);  S.Gmag = abs(G(half));  S.phase = phAll;
S.fFit = f(m);  S.phFit = ph;  S.phModel = p(1) + p(2)*2*pi*f(m);
S.X = abs(X(half));  S.Y = abs(Y(half));
end

% =========================================================================
%                         VELOCITY AND GMAX
% =========================================================================
function M = addVelocity(M, opts, f0, fRx)
L = [];
if ~isempty(opts.L), L = opts.L;
elseif ~isempty(opts.H_i) && ~isempty(opts.H_b), L = opts.H_i - opts.dH_c - opts.H_b;   % D8295 §7.3
end
for k = 1:numel(M)
    Ts = M(k).Ts;
    M(k).Ts_us = 1e6 * Ts;
    M(k).wavelengthsInPath_tx = f0 * (Ts - opts.Tc);   % L/lambda = f*(Ts - Tc), independent of L
    M(k).wavelengthsInPath_rx = fRx * (Ts - opts.Tc);
    M(k).Vs = NaN;  M(k).Gmax_MPa = NaN;
    if ~isempty(L) && Ts - opts.Tc > 0
        M(k).Vs = L / (Ts - opts.Tc);                    % D8295 Eq. 1
        if ~isempty(opts.rho), M(k).Gmax_MPa = opts.rho * M(k).Vs^2 / 1e6; end   % Eq. 3
    end
end
end

% =========================================================================
%                              PLOTTING
% =========================================================================
function info = figInfo(TX, RX, T, F, opts)
info.ftxLine = sprintf('f_{tx} = %.3f kHz  (full period %.1f \\mus; peak-trough: %.3f kHz)', ...
    T.f.primary/1e3, 1e6*T.period, T.f.peakTrough/1e3);
switch F.type
    case 'none', info.filtLine = 'receiver: unfiltered';
    case 'fft',  info.filtLine = sprintf('receiver: zero-phase FFT band-pass %.2f-%.1f kHz', F.band/1e3);
    otherwise,   info.filtLine = sprintf('receiver: Butterworth (order %d, filtfilt) %.2f-%.1f kHz', ...
                    opts.butterOrder, F.band/1e3);
end
info.files = sprintf('Tx: %s   |   Rx: %s', esc(TX.name), esc(RX.name));
if opts.rxPolarity < 0, info.files = [info.files '   |   Rx inverted']; end
info.vis = 'on';  if ~opts.showFigures, info.vis = 'off'; end
info.countsMode = strcmp(TX.mode, 'ADC counts') || strcmp(RX.mode, 'ADC counts');
end

function fig = newFig(name, info)
fig = figure('Name', name, 'Color', 'w', 'Visible', info.vis, 'Units', 'pixels', ...
    'Position', [80 80 1100 760]);
end

function ax = dualAxes(ax, tus, x, tusR, yrRaw, yF)
% transmitter (V) on the left axis, receiver (mV) on the right axis - D8295 Fig. 3 style
yyaxis(ax, 'left');
plot(ax, tus, x, '--', 'Color', [0 0.30 0.70], 'LineWidth', 1.4, 'DisplayName', 'Transmitter');
hold(ax, 'on');
ylabel(ax, 'Transmitter signal (V)');
yl = max(abs(x)) * 1.15;  ylim(ax, [-yl yl]);
yyaxis(ax, 'right');
hold(ax, 'on');
if ~isempty(yrRaw)
    plot(ax, tusR, 1e3*yrRaw, '-', 'Color', [0.85 0.55 0.45], 'LineWidth', 0.5, 'DisplayName', 'Receiver (raw)');
end
hold(ax, 'on');
plot(ax, tusR, 1e3*yF, '-', 'Color', [0.70 0.10 0.05], 'LineWidth', 1.6, 'DisplayName', 'Receiver (filtered)');
ylabel(ax, 'Receiver signal (mV)');
r = max(abs(1e3*[yF(:); yrRaw(:)])) * 1.15;  ylim(ax, [-r r]);
ax.YAxis(1).Color = [0 0.30 0.70];  ax.YAxis(2).Color = [0.70 0.10 0.05];
grid(ax, 'on');  box(ax, 'on');
xlabel(ax, 'Time from transmitter start (\mus)');
end

function fig = plotOverview(t, x, yr, y, T, F, P, info, opts)
fig = newFig('BE overview', info);
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
ax = nexttile(tl, [1 2]);
dualAxes(ax, tus, x, tus, yr, y);
yyaxis(ax, 'left');
xline(ax, 0, ':k', 'tx start', 'HandleVisibility', 'off');
xlim(ax, [tus(1) tus(end)]);
legend(ax, 'Location', 'northeast');
title(ax, {'Full records', info.filtLine});
ax = nexttile(tl);
plot(ax, 1e6*(t - T.tStart), x, 'Color', [0 0.3 0.7], 'LineWidth', 1.4); hold(ax, 'on');
plot(ax, 1e6*([T.tStart T.tPeak T.tMid T.tTrough T.tEnd] - T.tStart), ...
    [0 T.aPeak 0 T.aTrough 0], 'ko', 'MarkerFaceColor', 'y');
grid(ax, 'on');  xlim(ax, 1e6*[-0.3 1.3]*T.period);
xlabel(ax, 'Time from transmitter start (\mus)');  ylabel(ax, 'Transmitter (V)');
title(ax, {'Transmitter pulse and frequency', info.ftxLine});
ax = nexttile(tl);
nfft = 2^nextpow2(8*numel(x));  fa = (0:nfft/2-1).' / nfft / (t(2)-t(1));
Xs = abs(fft(x, nfft));  Yr = abs(fft(yr, nfft));  Yf = abs(fft(y, nfft));
Xs = Xs(1:nfft/2); Yr = Yr(1:nfft/2); Yf = Yf(1:nfft/2);
plot(ax, fa/1e3, Xs/max(Xs), 'Color', [0 0.3 0.7], 'LineWidth', 1.3, 'DisplayName', 'Transmitter'); hold(ax, 'on');
plot(ax, fa/1e3, Yr/max(Yf), 'Color', [0.85 0.55 0.45], 'DisplayName', 'Receiver raw');
plot(ax, fa/1e3, Yf/max(Yf), 'Color', [0.7 0.1 0.05], 'LineWidth', 1.3, 'DisplayName', 'Receiver filtered');
plot(ax, F.fAxis/1e3, F.H, 'k:', 'LineWidth', 1.1, 'DisplayName', 'Filter gain');
xline(ax, T.f.primary/1e3, '--', sprintf('f_{tx} %.2f kHz', T.f.primary/1e3), 'Color', [0 0.3 0.7], 'HandleVisibility', 'off');
xline(ax, P.fRx/1e3, '--', sprintf('f_{rx} %.2f kHz', P.fRx/1e3), 'Color', [0.7 0.1 0.05], ...
    'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
grid(ax, 'on');  xlim(ax, [0 min(fa(end), 8*T.f.primary)/1e3]);  ylim(ax, [0 1.3]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Normalised amplitude');
legend(ax, 'Location', 'northeast');  title(ax, 'Amplitude spectra');
title(tl, {'Bender element records', info.files}, 'FontWeight', 'bold');
if info.countsMode
    annotation(fig, 'textbox', [0.01 0.0 0.98 0.03], 'String', ...
        sprintf(['Amplitudes scaled as counts x (V/div) / %g; this factor is not verified for your scope ' ...
        'and affects amplitudes only, not times.'], opts.countsPerDiv), ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.4 0.4 0.4], 'Interpreter', 'none');
end
end

function fig = plotS2S(t, x, yr, y, T, P, m, info, opts) %#ok<INUSD>
fig = newFig('Start to Start', info);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
xr = 1e6 * [-0.3*T.period, max(1.6*T.period, (P.tPeak1 - T.tStart) + 0.6*T.period)];
for pane = 1:2
    ax = nexttile(tl);
    dualAxes(ax, tus, x, tus, yr, y);
    yyaxis(ax, 'right');
    yline(ax, 0, '-', 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
    if ~isnan(P.tNearField)
        plot(ax, 1e6*(P.tNearField - T.tStart), 1e3*P.aNearField, 'v', 'Color', [0.5 0 0.5], ...
            'MarkerFaceColor', [0.8 0.6 0.9], 'MarkerSize', 8, 'DisplayName', 'Near-field excursion');
    end
    plot(ax, 1e6*(P.tArrival - T.tStart), 0, 'o', 'Color', [0.7 0.1 0.05], 'MarkerFaceColor', 'y', ...
        'MarkerSize', 9, 'DisplayName', 'Rx arrival (baseline crossing)');
    yyaxis(ax, 'left');
    plot(ax, 0, 0, 's', 'Color', [0 0.3 0.7], 'MarkerFaceColor', 'y', 'MarkerSize', 9, ...
        'DisplayName', 'Tx start');
    xline(ax, 0, ':', 'Color', [0 0.3 0.7], 'HandleVisibility', 'off');
    xline(ax, 1e6*(P.tArrival - T.tStart), ':', 'Color', [0.7 0.1 0.05], 'HandleVisibility', 'off');
    if pane == 1
        xlim(ax, xr);  legend(ax, 'Location', 'southwest');
        drawSpan(ax, 0, 1e6*(P.tArrival - T.tStart), sprintf('T_s = %.1f \\mus', 1e6*m.Ts), 0.88);
        title(ax, {sprintf('Start to Start (ASTM D8295 §10.1.2):  T_s = %.1f \\mus', 1e6*m.Ts), info.ftxLine});
    else
        c = 1e6*(P.tArrival - T.tStart);  w = 1e6*0.35*T.period;
        xlim(ax, [c - w, c + w]);
        title(ax, 'Zoom on the receiver arrival');
    end
end
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotPeaks(t, x, yr, y, T, P, mP, mT, info, opts) %#ok<INUSD>
fig = newFig('Peak to Peak', info);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
xr = 1e6 * [-0.3*T.period, max(1.8*T.period, (P.tPeak1 - T.tStart) + 1.2*T.period)];
spec = {mP, T.tPeak, T.aPeak, P.tPeak1, P.aPeak1, 'peak', ...
        'Peak to Peak (ASTM D8295 §10.1.1)'; ...
        mT, T.tTrough, T.aTrough, P.tTrough1, P.aTrough1, 'trough', ...
        'Trough to Trough (second-lobe check, not part of D8295)'};
for pane = 1:2
    [m, ttx, atx, trx, arx, word, ttl] = spec{pane, :};
    ax = nexttile(tl);
    dualAxes(ax, tus, x, tus, yr, y);
    yyaxis(ax, 'right');
    if ~isnan(trx)
        plot(ax, 1e6*(trx - T.tStart), 1e3*arx, 'o', 'Color', [0.7 0.1 0.05], 'MarkerFaceColor', 'y', ...
            'MarkerSize', 9, 'DisplayName', ['Rx 1st ' word]);
        xline(ax, 1e6*(trx - T.tStart), ':', 'Color', [0.7 0.1 0.05], 'HandleVisibility', 'off');
    end
    yyaxis(ax, 'left');
    plot(ax, 1e6*(ttx - T.tStart), atx, 's', 'Color', [0 0.3 0.7], 'MarkerFaceColor', 'y', ...
        'MarkerSize', 9, 'DisplayName', ['Tx ' word]);
    xline(ax, 1e6*(ttx - T.tStart), ':', 'Color', [0 0.3 0.7], 'HandleVisibility', 'off');
    xlim(ax, xr);  legend(ax, 'Location', 'southwest');
    if isnan(m.Ts)
        title(ax, {[ttl ':  not determined'], info.ftxLine});
    else
        drawSpan(ax, 1e6*(ttx - T.tStart), 1e6*(trx - T.tStart), sprintf('T_s = %.1f \\mus', 1e6*m.Ts), 0.90);
        title(ax, {sprintf('%s:  T_s = %.1f \\mus', ttl, 1e6*m.Ts), info.ftxLine});
    end
end
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotCC(t, a, b, C, T, m, info, opts, ttl) %#ok<INUSD>
fig = newFig(ttl, info);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
xr = 1e6 * [-0.3*T.period, max(2*T.period, C.lag + 1.5*T.period)];
% (1) the two signals that are correlated
ax = nexttile(tl);
dualAxes(ax, tus, a, tus, [], b);
xlim(ax, xr);  legend(ax, 'Location', 'northeast');
if C.envelope, title(ax, {'Signal envelopes (|analytic signal|)', info.ftxLine});
else,          title(ax, {'Transmitter and filtered receiver', info.ftxLine});
end
% (2) the cross-correlation function
ax = nexttile(tl);
plot(ax, 1e6*C.tl, C.c, 'k-', 'LineWidth', 1.2, 'DisplayName', 'Normalised CC'); hold(ax, 'on');
plot(ax, 1e6*C.lag, C.peak, 'o', 'Color', [0.7 0.1 0.05], 'MarkerFaceColor', 'y', 'MarkerSize', 9, ...
    'DisplayName', sprintf('max at %.1f \\mus (CC = %.3f)', 1e6*C.lag, C.peak));
if ~C.envelope && isfield(C, 'secondLag') && ~isnan(C.secondLag)
    plot(ax, 1e6*C.secondLag, C.secondPeak, 'd', 'Color', [0.4 0.4 0.4], 'MarkerSize', 8, ...
        'DisplayName', sprintf('runner-up at %.1f \\mus (%.0f %%)', 1e6*C.secondLag, 100*C.secondPeak/C.peak));
end
xline(ax, 0, ':k', 'HandleVisibility', 'off');
grid(ax, 'on');  xlim(ax, [-xr(2) xr(2)]);  ylim(ax, [-1 1]);
xlabel(ax, 'Lag of receiver relative to transmitter (\mus)');  ylabel(ax, 'Normalised CC');
legend(ax, 'Location', 'southwest');
title(ax, sprintf('%s:  T_s = %.1f \\mus', ttl, 1e6*m.Ts));
% (3) alignment check: transmitter shifted by the CC lag over the receiver
ax = nexttile(tl);
plot(ax, tus + 1e6*C.lag, a / max(abs(a)), '--', 'Color', [0 0.3 0.7], 'LineWidth', 1.4, ...
    'DisplayName', sprintf('Transmitter shifted by %.1f \\mus', 1e6*C.lag)); hold(ax, 'on');
plot(ax, tus, b / max(abs(b)), '-', 'Color', [0.7 0.1 0.05], 'LineWidth', 1.6, 'DisplayName', 'Receiver');
grid(ax, 'on');  xlim(ax, xr);  ylim(ax, [-1.15 1.15]);
xlabel(ax, 'Time from transmitter start (\mus)');  ylabel(ax, 'Normalised amplitude');
legend(ax, 'Location', 'southwest');  title(ax, 'Alignment check (each trace scaled to its own maximum)');
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotCPS(S, m, info)
fig = newFig('Cross-power spectrum', info);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
fmax = min(S.f(end), 4 * mean(S.band));
ax = nexttile(tl);
plot(ax, S.f/1e3, S.X/max(S.X), '--', 'Color', [0 0.3 0.7], 'LineWidth', 1.4, 'DisplayName', '|Transmitter|'); hold(ax, 'on');
plot(ax, S.f/1e3, S.Y/max(S.Y), '-', 'Color', [0.7 0.1 0.05], 'LineWidth', 1.4, 'DisplayName', '|Receiver (filtered)|');
plot(ax, S.f/1e3, S.Gmag/max(S.Gmag), 'k:', 'LineWidth', 1.2, 'DisplayName', '|Cross-power spectrum|');
xregion(ax, S.band(1)/1e3, S.band(2)/1e3, 'FaceColor', [0.9 0.8 0.3], 'FaceAlpha', 0.25, 'DisplayName', 'Fit band');
grid(ax, 'on');  xlim(ax, [0 fmax/1e3]);  ylim(ax, [0 1.15]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Normalised magnitude');  legend(ax, 'Location', 'northeast');
title(ax, {'Amplitude spectra of both signals', info.ftxLine});
ax = nexttile(tl);
k = S.f <= fmax;
plot(ax, S.f(k)/1e3, S.phase(k), '-', 'Color', [0.6 0.6 0.6], 'DisplayName', 'Unwrapped phase'); hold(ax, 'on');
plot(ax, S.fFit/1e3, S.phFit, 'k.', 'MarkerSize', 8, 'DisplayName', 'Fitted points');
plot(ax, S.fFit/1e3, S.phModel, 'r-', 'LineWidth', 1.8, ...
    'DisplayName', sprintf('slope \\rightarrow \\tau = %.1f \\mus (R^2 = %.3f)', 1e6*S.tau, S.R2));
grid(ax, 'on');  xlim(ax, [0 fmax/1e3]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Phase of cross-power spectrum (rad)');  legend(ax, 'Location', 'southwest');
title(ax, sprintf('Cross-power spectrum phase slope (group delay):  T_s = %.1f \\mus', 1e6*m.Ts));
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotSummary(M, Craw, info, opts)
fig = newFig('Summary', info);
ax = axes(fig);
n = numel(M);  ts = [M.Ts_us];
cols = zeros(n, 3);
for k = 1:n
    if contains(M(k).basis, 'ASTM'),         cols(k, :) = [0.10 0.45 0.25];
    elseif contains(M(k).basis, 'informational'), cols(k, :) = [0.65 0.65 0.65];
    else,                                    cols(k, :) = [0.25 0.40 0.75];
    end
end
b = barh(ax, 1:n, ts, 'FaceColor', 'flat');  b.CData = cols;
hold(ax, 'on');
for k = 1:n
    if isnan(ts(k)), lab = '  not determined'; else, lab = sprintf('  %.1f \\mus', ts(k)); end
    if ~isnan(M(k).Vs), lab = [lab sprintf('   V_s = %.0f m/s', M(k).Vs)]; end           %#ok<AGROW>
    if ~isnan(M(k).Gmax_MPa), lab = [lab sprintf('   G_{max} = %.0f MPa', M(k).Gmax_MPa)]; end %#ok<AGROW>
    if ~strcmp(M(k).quality, 'ok'), lab = [lab '   (check)']; end                           %#ok<AGROW>
    text(ax, max(0, ts(k)), k, lab, 'VerticalAlignment', 'middle', 'FontSize', 9);
end
std2 = mean(ts(1:2), 'omitnan');
if ~isnan(std2)
    xline(ax, std2, '--', sprintf('mean of D8295 methods %.1f \\mus', std2), 'Color', [0.10 0.45 0.25]);
end
set(ax, 'YTick', 1:n, 'YTickLabel', {M.name}, 'YDir', 'reverse');
good = ts(~isnan(ts));
if isempty(good), good = 1; end
xlim(ax, [min(0, min(good)), 1.6 * max(good)]);
grid(ax, 'on');  xlabel(ax, 'Shear-wave travel time T_s (\mus)');
title(ax, {'Travel time by method', info.ftxLine, ...
    'green: ASTM D8295   blue: other methods (§10.2, need validation)   grey: informational', ...
    sprintf('unfiltered-receiver CC check: %.1f \\mus   |   T_c = %.1f \\mus', 1e6*Craw.lag, 1e6*opts.Tc)});
end

function drawSpan(ax, x1, x2, label, yFrac)
yl = ylim(ax);  yv = yl(1) + yFrac * diff(yl);
plot(ax, [x1 x2], [yv yv], 'k-', 'LineWidth', 1.1, 'HandleVisibility', 'off');
plot(ax, [x1 x2], [yv yv], 'k|', 'MarkerSize', 12, 'LineWidth', 1.1, 'HandleVisibility', 'off');
text(ax, (x1 + x2)/2, yv, label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontWeight', 'bold', 'BackgroundColor', 'w', 'Margin', 1);
end

function [ts, ok] = manualPick(t, x, y, T, info)
fig = newFig('Manual pick', info);  ax = axes(fig);
tus = 1e6 * (t - T.tStart);
dualAxes(ax, tus, x, tus, [], y);
xlim(ax, 1e6 * [-0.3 3] * T.period);
title(ax, {'Manual pick: click 1) the transmitter reference point, 2) the matching receiver point', ...
    'Use the same feature on both traces (start/start or peak/peak). Press Enter to skip.'});
[gx, ~] = ginput(2);
ok = numel(gx) == 2 && gx(2) > gx(1);
if ok
    ts = 1e-6 * (gx(2) - gx(1));
    yyaxis(ax, 'left');  xline(ax, gx(1), 'b-');  yyaxis(ax, 'right');  xline(ax, gx(2), 'r-');
else
    ts = NaN;
end
end

% =========================================================================
%                              REPORT / OUTPUT
% =========================================================================
function printReport(R, fid)
if nargin < 2, fid = 1; end
T = R.transmitter;  F = R.filter;  P = R.picks;  M = R.methods;  o = R.options;
[~, a, b] = fileparts(R.files.tx);  [~, c, d] = fileparts(R.files.rx);
fprintf(fid, '\n=== Bender element travel-time analysis (ASTM D8295-19) ===\n');
fprintf(fid, 'Transmitter file : %s\nReceiver file    : %s\n', [a b], [c d]);
fprintf(fid, 'Sampling period  : %.3g us  (%.3g MHz), %d points, record %.1f us\n', ...
    1e6*R.dt, 1e-6/R.dt, numel(T.x), 1e6*R.dt*numel(T.x));
fprintf(fid, '\nTransmitter pulse\n');
fprintf(fid, '  start (5-30%% rise extrapolated) : %8.2f us after record start (crossing: %.2f us)\n', ...
    1e6*T.tStart, 1e6*T.tStartCrossing);
fprintf(fid, '  frequency, full period            : %8.3f kHz   <- used\n', T.f.fullPeriod/1e3);
fprintf(fid, '  frequency, 1st / 2nd half period  : %8.3f / %.3f kHz\n', T.f.halfPeriod1/1e3, T.f.halfPeriod2/1e3);
fprintf(fid, '  frequency, peak-to-trough x 2     : %8.3f kHz\n', T.f.peakTrough/1e3);
fprintf(fid, '  spectral peak (1-cycle burst)     : %8.3f kHz  (sits below the nominal f for a single cycle)\n', ...
    T.f.spectralPeak/1e3);
fprintf(fid, '  amplitude (peak / trough)         : %+.2f / %+.2f V (scaled, see countsPerDiv)\n', T.aPeak, T.aTrough);
fprintf(fid, '\nReceiver\n');
fprintf(fid, '  filter            : %s, band %.2f-%.2f kHz\n', F.type, F.band/1e3);
fprintf(fid, '  noise (pre-trigger, robust std): raw %.3g mV, filtered %.3g mV; peak SNR %.0f\n', ...
    1e3*F.noiseRaw, 1e3*F.noiseFilt, P.snr);
fprintf(fid, '  dominant frequency: %.3f kHz  (f_rx / f_tx = %.2f; D8295 §9.8 expects about the same)\n', ...
    P.fRx/1e3, P.fRx/T.f.primary);
if ~isnan(P.tNearField)
    fprintf(fid, '  near-field excursion at %.1f us after tx start (%.3g mV)\n', ...
        1e6*(P.tNearField - T.tStart), 1e3*P.aNearField);
end
fprintf(fid, '\n  %-28s %-34s %9s %8s %8s %9s  %s\n', 'Method', 'Basis', 'Ts (us)', 'f*Ts', ...
    'Vs(m/s)', 'Gmax(MPa)', 'Note');
for k = 1:numel(M)
    fprintf(fid, '  %-28s %-34s %9.1f %8.2f %8.0f %9.1f  %s%s\n', M(k).name, M(k).basis, M(k).Ts_us, ...
        M(k).wavelengthsInPath_tx, M(k).Vs, M(k).Gmax_MPa, M(k).note, ...
        ternary(strcmp(M(k).quality, 'ok'), '', '  [CHECK]'));
end
fprintf(fid, '  Filter-sensitivity checks on the UNFILTERED receiver: CC %.1f us, Start-to-Start %.1f us\n', ...
    1e6*R.ccRaw.lag, 1e6*(P.tArrivalRaw - T.tStart));
fprintf(fid, '  f*Ts = travel path length in transmitted wavelengths (L/lambda); Tc = %.2f us applied.\n', 1e6*o.Tc);
if o.Tc == 0
    fprintf(fid, '  NOTE: Tc = 0. D8295 §8.1 asks for a tip-to-tip calibration of the system delay.\n');
end
s2s = M(1).Ts;  p2p = M(2).Ts;
if ~isnan(s2s) && ~isnan(p2p)
    fprintf(fid, '  Start-to-Start vs Peak-to-Peak differ by %.1f us (%.0f %% of their mean).\n', ...
        1e6*abs(s2s - p2p), 200*abs(s2s - p2p)/(s2s + p2p));
end
fprintf(fid, '\n');
end

function folder = saveOutputs(R, figs, opts)
folder = opts.outputFolder;
if isempty(folder)
    [p, n] = fileparts(R.files.rx);
    folder = fullfile(p, ['BE_results_' n]);
end
if ~exist(folder, 'dir'), mkdir(folder); end
for k = 1:numel(figs)
    if ~isgraphics(figs(k)), continue; end
    nm = regexprep(get(figs(k), 'Name'), '[^\w]+', '_');
    exportgraphics(figs(k), fullfile(folder, sprintf('%02d_%s.png', k, nm)), 'Resolution', 200);
end
% methods table (plain CSV, readable anywhere)
fid = fopen(fullfile(folder, 'travel_times.csv'), 'w');
fprintf(fid, 'Method,Basis,Ts_s,Ts_us,f_tx_times_Ts,Vs_m_s,Gmax_MPa,Quality,Note\n');
M = R.methods;
for k = 1:numel(M)
    fprintf(fid, '"%s","%s",%.9g,%.3f,%.4f,%.4g,%.4g,%s,"%s"\n', M(k).name, M(k).basis, M(k).Ts, ...
        M(k).Ts_us, M(k).wavelengthsInPath_tx, M(k).Vs, M(k).Gmax_MPa, M(k).quality, strrep(M(k).note, '"', ''''));
end
fclose(fid);
fid = fopen(fullfile(folder, 'report.txt'), 'w');  printReport(R, fid);  fclose(fid);
Rsave = rmfield(R, 'figures');  %#ok<NASGU>
save(fullfile(folder, 'BE_results.mat'), 'Rsave');
fprintf('Results saved in: %s\n', folder);
end

% =========================================================================
%                              HELPERS
% =========================================================================
function r = mrow(name, tag, basis, Ts, ok, note)
if ok && ~isnan(Ts) && Ts > 0, q = 'ok'; else, q = 'check'; end
r = struct('name', name, 'tag', tag, 'basis', basis, 'Ts', Ts, 'quality', q, 'note', note);
end

function tc = crossTime(t, z, k)
% time where z crosses zero between samples k and k+1 (linear interpolation)
k = max(1, min(numel(z) - 1, k));
if z(k+1) == z(k), tc = t(k); return; end
tc = t(k) - z(k) * (t(k+1) - t(k)) / (z(k+1) - z(k));
end

function tr = flankRoot(t, z, idx, zLo, zHi)
% zero of a straight line fitted to the samples of one flank with zLo <= z <= zHi
idx = idx(:);
use = idx(z(idx) >= zLo & z(idx) <= zHi);
if numel(use) >= 3 && numel(unique(z(use))) >= 2
    t0 = t(use(1));
    p = polyfit(t(use) - t0, z(use), 1);
    if p(1) ~= 0, tr = t0 - p(2)/p(1); return; end
end
k = idx(find(z(idx(1:end-1)) .* z(idx(2:end)) <= 0 & z(idx(2:end)) ~= z(idx(1:end-1)), 1));
if isempty(k), tr = t(idx(1)); else, tr = crossTime(t, z, k); end
end

function [tp, ap] = refineExtremum(t, z, i1, i2, sgn)
% sub-sample extremum: quadratic least-squares fit to the top 10 % of the lobe
i1 = max(1, i1);  i2 = min(numel(z), i2);
w = sgn * z(i1:i2);
[m, j] = max(w);  j = j + i1 - 1;
lo = j;  while lo > i1 && sgn*z(lo-1) >= 0.9*m, lo = lo - 1; end
hi = j;  while hi < i2 && sgn*z(hi+1) >= 0.9*m, hi = hi + 1; end
if hi - lo >= 2
    tt = t(lo:hi) - t(j);
    p = polyfit(tt, z(lo:hi), 2);
    tv = -p(2) / (2*p(1));
    if sgn*p(1) < 0 && tv >= tt(1) && tv <= tt(end)
        tp = t(j) + tv;  ap = polyval(p, tv);  return;
    end
    tp = mean(t(lo:hi));  ap = z(j);  return;            % flat (clipped/quantised) top
end
tp = t(j);  ap = z(j);
end

function s = robustStd(v)
s = 1.4826 * median(abs(v - median(v)));
if s == 0, s = std(v); end
if s == 0, s = eps; end
end

function e = envAnalytic(v)
% magnitude of the analytic signal (Hilbert envelope), base MATLAB only
v = v(:);  N = numel(v);  h = zeros(N, 1);
if mod(N, 2) == 0, h([1 N/2+1]) = 1; h(2:N/2) = 2;
else,              h(1) = 1;         h(2:(N+1)/2) = 2;
end
e = abs(ifft(fft(v) .* h));
end

function s = esc(s)
s = strrep(s, '_', '\_');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
