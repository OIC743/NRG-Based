%% =========================================================================
%  MEASURED BENDER-ELEMENT FREQUENCY SWEEP -> COMPARISON WORKBOOK
%  BE_SweepToWorkbook  |  input for BE_CompareSweeps
%  =========================================================================
%
%  HOW TO RUN: edit the USER SETTINGS block and run the script (F5). Leave
%  sweepFile empty to be asked for the workbook.
%
%  INPUT: one sheet with, for every frequency, a 'Time' column followed by
%  'Inpt-<f>kHz' (transmitter) and 'Otpt-<f>kHz' (receiver) columns, e.g.
%     Time | Inpt-4kHz | Otpt-4kHz | Time_C.C | C.C-4kHz | Time | Inpt-8kHz | ...
%  The rows below the titles may hold a second title row (text); the data
%  start at the first numeric row. Columns other than Time / Inpt / Otpt
%  (e.g. 'Time_C.C', 'C.C-...') are ignored. Each frequency may have its own
%  time step and length.
%
%  WHAT IT DOES, per frequency, with the analysis of BE_TravelTime_V6 (the
%  functions below are copied from it unchanged): transmitter start and
%  frequency, all travel-time methods - peak to peak (reported), start to
%  start, trough to trough, an independent cross-correlation of the two
%  signals, envelope cross-correlation, cross-power spectrum, first
%  deflection - with their quality flags, Vs = L / (Ts - Tc), near field
%  and crosstalk checks. No filter is applied (cfg.filterType = 'none'),
%  because the data are supplied filtered.
%  RECEIVER POLARITY (cfg.rxPolarity = 'auto'): for each frequency the
%  cross-correlation of transmitter and receiver is examined; if its
%  largest excursion is negative, that frequency votes for an inverted
%  receiver. The majority decides for all frequencies (one wiring); each
%  vote is printed and stored. Set +1 or -1 to override.
%
%  OUTPUT: <sweep>_BE.xlsx in the layout BE_CompareSweeps reads (sheets
%  Summary, Waveforms, CrossCorrelation, Parameters; DATA TYPE = MEASURED).
%  Waveforms and cross-correlations are put on one common time grid there,
%  from the transmitter start to the end of the shortest record (linear
%  interpolation, for plotting only - all travel times come from the
%  original samples). The receiver is stored with the polarity used.
%  =========================================================================

%% ============================ USER SETTINGS ==============================
sweepFile = '';                         % measured sweep workbook ('' -> file dialog)

cfg = struct();
cfg.sheet          = 1;                 % sheet name or number
cfg.timeUnit       = 1e-6;              % s per unit of the Time columns (1e-6: microseconds)
cfg.L              = 20.6e-3;           % m, travel length tip to tip
cfg.Tc             = 5.2e-6;            % s, system time delay (tip-to-tip calibration)
cfg.testFrequency  = [];                % kHz, frequency of the reported test ([] -> set it in BE_CompareSweeps)
cfg.rxPolarity     = 'auto';            % 'auto' | +1 | -1
cfg.frequencyBasis = 'nominal';         % 'nominal' (column titles) | 'measured' (transmitter) for f, R_d, L/lambda
cfg.filterType     = 'none';            % data supplied filtered; 'fft' to band-pass as V6 does
cfg.minTravelTime  = 0;                 % s, nothing earlier is picked (crosstalk)
cfg.maxTravelTime  = [];                % s, [] -> end of the record
cfg.outputFile     = '';                % '' -> <sweep>_BE.xlsx next to the input
%% =========================================================================

if isempty(sweepFile)
    [f, p] = uigetfile({'*.xlsx;*.xls', 'Measured sweep (*.xlsx, *.xls)'}, 'Select the measured sweep workbook');
    if isequal(f, 0), disp('No workbook selected - cancelled.'); return; end
    sweepFile = fullfile(p, f);
end
if ~isfile(sweepFile), error('BEW:file', 'File not found: %s', sweepFile); end
[pIn, nIn, eIn] = fileparts(sweepFile);
outFile = cfg.outputFile;
if isempty(outFile), outFile = fullfile(pIn, [nIn '_BE.xlsx']); end

% ---- 1. read the sweep ------------------------------------------------------
sw = readMeasuredSweep(sweepFile, cfg);
n = numel(sw);
fprintf('\n%s: %d frequencies (%s kHz)\n', [nIn eIn], n, strjoin(arrayfun(@(s) sprintf('%g', s.fNominal), sw, ...
    'UniformOutput', false), ', '));

% ---- 2. analysis options (as BE_TravelTime_V6, no figures) -----------------
opts = analysisOptions(cfg);

% ---- 3. receiver polarity -----------------------------------------------------
vote = zeros(n, 1);  margin = NaN(n, 1);
if ischar(cfg.rxPolarity) && strcmpi(cfg.rxPolarity, 'auto')
    o1 = opts;  o1.rxPolarity = 1;
    for k = 1:n
        R1 = analysePair(sw(k).t, sw(k).x, sw(k).y, o1);
        [vote(k), margin(k)] = polarityVote(R1.cc, opts);
    end
    pol = 1;  if sum(vote) < 0, pol = -1; end
    if sum(vote) == 0
        warning('BEW:polarity', 'Polarity votes are tied; +1 (as recorded) is used. Set cfg.rxPolarity to decide.');
    elseif any(vote == -pol)
        warning('BEW:polarity', ['Polarity votes differ between frequencies (%s); the majority (%+d) is used ' ...
            'for all. Check the wiring or set cfg.rxPolarity.'], mat2str(vote.'), pol);
    end
    polBasis = 'auto: majority of the cross-correlation votes';
else
    pol = cfg.rxPolarity;  polBasis = 'set by the user';
end
opts.rxPolarity = pol;

% ---- 4. analysis of every frequency -------------------------------------------
R = cell(n, 1);
for k = 1:n
    R{k} = analysePair(sw(k).t, sw(k).x, sw(k).y, opts);
end
res = collectResults(sw, R, cfg, vote, margin);
printResults(res, sw, pol, polBasis, cfg, 1);

% ---- 5. comparison workbook ---------------------------------------------------
writeSweepWorkbook(outFile, sw, R, res, cfg, pol, polBasis, [nIn eIn]);
fprintf('Workbook for BE_CompareSweeps written: %s\n', outFile);

% =========================================================================
%                                 READING
% =========================================================================
function sw = readMeasuredSweep(file, cfg)
% Time / Inpt-<f> / Otpt-<f> column groups -> struct array (t in s, signals as given)
C = readcell(file, 'Sheet', cfg.sheet);
hdr = cellfun(@cellText, C(1, :), 'UniformOutput', false);
hdr = strtrim(hdr);
iIn = find(~cellfun(@isempty, regexpi(hdr, '^Inpt-', 'once')));
if isempty(iIn), error('BEW:format', 'No "Inpt-..." column titles found in the first row.'); end
sw = struct('label', {}, 'fNominal', {}, 't', {}, 'x', {}, 'y', {}, 'dt', {}, 'columns', {});
for j = iIn
    label = regexprep(hdr{j}, '^Inpt-', '', 'ignorecase');
    jOut = find(strcmpi(hdr, ['Otpt-' label]), 1);
    jT = find(strcmpi(hdr(1:j-1), 'Time'), 1, 'last');
    if isempty(jOut) || isempty(jT)
        error('BEW:format', 'Column "%s" has no matching "Otpt-%s" or preceding "Time" column.', hdr{j}, label);
    end
    tok = regexpi(label, '([\d.]+)\s*kHz', 'tokens', 'once');
    if isempty(tok), error('BEW:format', 'Cannot read a frequency in kHz from "%s".', hdr{j}); end
    v = cellfun(@cellNum, C(2:end, [jT j jOut]));
    v = v(all(isfinite(v), 2), :);                       % numeric rows of this group
    if size(v, 1) < 100, error('BEW:format', '%s: only %d numeric rows.', hdr{j}, size(v, 1)); end
    t = v(:, 1) * cfg.timeUnit;
    dts = diff(t);  dt = median(dts);
    if ~(dt > 0) || any(dts <= 0), error('BEW:format', '%s: time is not increasing.', hdr{j}); end
    if max(abs(dts - dt)) > 0.01 * dt
        warning('BEW:format', '%s: time steps are not uniform; a constant step of %.4g s is used.', hdr{j}, dt);
    end
    k = numel(sw) + 1;
    sw(k).label = label;  sw(k).fNominal = str2double(tok{1});
    sw(k).t = t(1) + (0:numel(t) - 1).' * dt;  sw(k).x = v(:, 2);  sw(k).y = v(:, 3);
    sw(k).dt = dt;  sw(k).columns = sprintf('%s / %s / %s', hdr{jT}, hdr{j}, hdr{jOut});
end
[~, order] = sort([sw.fNominal]);
sw = sw(order);
end

function opts = analysisOptions(cfg)
% the option fields the V6 analysis functions use, with V6's defaults
opts = struct('rxPolarity', 1, 'filterType', lower(cfg.filterType), 'filterBand', [], ...
    'filterBandFactor', [0.25 4], 'butterOrder', 4, 'minTravelTime', cfg.minTravelTime, ...
    'maxTravelTime', cfg.maxTravelTime, 'ampFrac', 0.25, 'noiseK', 4, 'minSNR', 10, ...
    'L', cfg.L, 'H_i', [], 'dH_c', 0, 'H_b', [], 'Tc', cfg.Tc, 'rho', []);
if ~ismember(opts.filterType, {'none', 'fft', 'butter'})
    error('BEW:opt', 'cfg.filterType must be ''none'', ''fft'' or ''butter''.');
end
end

% =========================================================================
%                     ANALYSIS (as analyseRecord of V6)
% =========================================================================
function R = analysePair(t, x, yr, opts)
% analysis of one transmitter / receiver pair, as in BE_TravelTime_V6
% (analyseRecord) without figures, report or files
dt = t(2) - t(1);  fs = 1/dt;  N = numel(t);
T = analyseTransmitter(t, x);
x = x - T.baseline;
f0 = T.f.primary;
iPre = t < T.tStart;
if nnz(iPre) < 20
    warning('BE:shortPretrigger', ['Fewer than 20 pre-trigger samples; receiver offset ' ...
        'and noise estimates are unreliable.']);
    iPre(1:min(20, N)) = true;
end
yr = yr - mean(yr(iPre));
[y, F] = filterReceiver(yr, fs, f0, opts);
y  = opts.rxPolarity * y;
yr = opts.rxPolarity * yr;
F.nSmooth = max(1, round(0.05 * T.period / dt));
ys = movingMean(yr, F.nSmooth);
F.noiseRaw    = robustStd(yr(iPre));
F.noiseFilt   = max(robustStd(y(iPre)), F.noiseRaw * sqrt(mean(F.H.^2)));
F.noiseSmooth = max(robustStd(ys(iPre)), F.noiseRaw * sqrt(1/F.nSmooth + 1/nnz(iPre)));
X = crosstalkCheck(t, x, ys, T, F, opts);
P = pickReceiver(t, y, yr, ys, T, F, opts);
sigOK = P.snr >= opts.minSNR;
M = struct('name', {}, 'tag', {}, 'basis', {}, 'Ts', {}, 'quality', {}, 'note', {});
M(end+1) = mrow('Start to Start',     'S2S', 'ASTM D8295 §10.1.2', P.tArrival - T.tStart, P.ok && sigOK, '');
M(end+1) = mrow('Peak to Peak',       'P2P', 'ASTM D8295 §10.1.1', P.tPeak1 - T.tPeak, P.ok && sigOK, '');
M(end+1) = mrow('Trough to Trough',   'T2T', 'check (not in D8295)', P.tTrough1 - T.tTrough, ...
               P.ok && sigOK && ~isnan(P.tTrough1), '');
C  = crossCorr(x, y, dt, T, opts, false);
M(end+1) = mrow('Cross-correlation',  'CC', 'D8295 §10.2 (other)', C.lag, C.ok && sigOK, '');
CE = crossCorr(x, y, dt, T, opts, true);
M(end+1) = mrow('Envelope cross-correlation', 'ECC', 'D8295 §10.2 (other)', CE.lag, CE.ok && sigOK, '');
S  = crossSpectrum(x, y, fs, f0, F);
M(end+1) = mrow('Cross-power spectrum', 'CPS', 'D8295 §10.2 (other)', S.tau, S.ok && sigOK, '');
M(end+1) = mrow('First deflection',   'FD', 'informational (near-field onset)', ...
               P.tFirstDev - T.tStart, ~isnan(P.tFirstDev) && sigOK, '');
tsAll = [M.Ts];
tMaxTT = Inf;  if ~isempty(opts.maxTravelTime), tMaxTT = opts.maxTravelTime; end
M = flagRows(M, tsAll < opts.minTravelTime | tsAll > tMaxTT, 'outside the search window');
if X.detected
    M = flagRows(M, tsAll < X.window(2) - T.tStart, 'inside the crosstalk window');
end
if T.extraCycles
    M = flagRows(M, strcmp({M.tag}, 'ECC'), 'transmitter is not a single pulse');
end
M = addVelocity(M, opts, f0, P.fPeakTrough);
R = struct('transmitter', T, 'filter', F, 'crosstalk', X, 'picks', P, 'cc', C, 'methods', M, ...
    'signals', struct('t', t, 'tx', x, 'rxRaw', yr, 'rxFiltered', y));
end

function [v, m] = polarityVote(C, opts)
% +1 if the largest cross-correlation excursion in the lag window is
% positive, -1 if negative; m = |max| - |min| (size of the decision)
k = C.tl >= opts.minTravelTime;
if ~isempty(opts.maxTravelTime), k = k & C.tl <= opts.maxTravelTime; end
pos = max(C.c(k));  neg = -min(C.c(k));
v = sign(pos - neg);  m = pos - neg;
end

% =========================================================================
%                          RESULTS AND WORKBOOK
% =========================================================================
function res = collectResults(sw, R, cfg, vote, margin)
tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
n = numel(sw);
res.tags = tags;
res.fNominal = [sw.fNominal].';
res.fMeasured = cellfun(@(r) r.transmitter.f.primary, R) / 1e3;
if strcmpi(cfg.frequencyBasis, 'measured'), res.f = res.fMeasured; else, res.f = res.fNominal; end
res.Ts = NaN(n, 7);  res.quality = cell(n, 7);  res.Vs = NaN(n, 7);
for k = 1:n
    for j = 1:7
        m = R{k}.methods(strcmp({R{k}.methods.tag}, tags{j}));
        res.Ts(k, j) = m.Ts;  res.quality{k, j} = m.quality;  res.Vs(k, j) = m.Vs;
    end
end
res.LL = 1e3 * res.f .* (res.Ts(:, 2) - cfg.Tc);       % L/lambda = f (T_pp - Tc)
res.snr = cellfun(@(r) r.picks.snr, R);
res.crosstalk = cellfun(@(r) r.crosstalk.detected, R);
res.vote = vote;  res.margin = margin;
res.rxPeak_ms = NaN(n, 1);  res.rxPeakNorm = NaN(n, 1);  res.txPeak_ms = NaN(n, 1);
res.s2s_ms = NaN(n, 1);  res.nfStart_ms = NaN(n, 1);  res.nfEnd_ms = NaN(n, 1);  res.bump = zeros(n, 1);
for k = 1:n
    T = R{k}.transmitter;  P = R{k}.picks;  y = R{k}.signals.rxFiltered;
    res.rxPeak_ms(k) = 1e3 * (P.tPeak1 - T.tStart);
    res.rxPeakNorm(k) = P.aPeak1 / max(abs(y));
    res.txPeak_ms(k) = 1e3 * (T.tPeak - T.tStart);
    res.s2s_ms(k) = 1e3 * (P.tArrival - T.tStart);
    if ~isnan(P.tNearField)                              % near field confirmed in the raw trace
        tOn = P.tFirstDev;  if isnan(tOn), tOn = P.tNearField; end
        res.nfStart_ms(k) = 1e3 * (tOn - T.tStart);
        res.nfEnd_ms(k) = 1e3 * (P.tArrival - T.tStart);
        res.bump(k) = abs(P.aNearField / P.aPeak1);
    end
end
end

function printResults(res, sw, pol, polBasis, cfg, fid)
fprintf(fid, ['Receiver polarity used: %+d (%s); L = %.2f mm, Tc = %.2f us, filter: %s, ' ...
    'f basis: %s\n'], pol, polBasis, 1e3 * cfg.L, 1e6 * cfg.Tc, cfg.filterType, cfg.frequencyBasis);
fprintf(fid, '%7s %8s %6s %9s %8s %9s %8s %9s %6s %6s %7s %6s %s\n', 'f kHz', 'f_tx kHz', 'vote', ...
    'T_pp us', 'Vs_pp', 'T_cc us', 'Vs_cc', 'T_ss us', 'L/lam', 'SNR', 'xtalk', 'NF', 'quality P2P / CC');
for k = 1:numel(res.f)
    fprintf(fid, '%7.2f %8.3f %+6d %9.2f %8.2f %9.2f %8.2f %9.2f %6.2f %6.0f %7d %6.2f %s / %s\n', ...
        res.fNominal(k), res.fMeasured(k), res.vote(k), 1e6 * res.Ts(k, 2), res.Vs(k, 2), ...
        1e6 * res.Ts(k, 4), res.Vs(k, 4), 1e6 * res.Ts(k, 1), res.LL(k), res.snr(k), res.crosstalk(k), ...
        res.bump(k), res.quality{k, 2}, res.quality{k, 4});
end
fprintf(fid, ['vote: +1/-1 = sign of the largest cross-correlation excursion (polarity as recorded); ' ...
    'NF = near-field excursion / first peak (0 = none confirmed)\n\n']);
end

function writeSweepWorkbook(file, sw, R, res, cfg, pol, polBasis, source)
% layout of the V6 calibration workbook, which BE_CompareSweeps reads
if isfile(file), delete(file); end
n = numel(sw);  tags = res.tags;
hdr = [{'f_kHz', 'f_tx_measured_kHz', 'L_over_lambda'}, strcat('Ts_', tags, '_us'), ...
       {'Vs_PP_m_s', 'Vs_S2S_m_s', 'Vs_CC_m_s', 'user_entered'}, strcat('quality_', tags), ...
       {'rx_peak_ms', 'rx_peak_norm', 'tx_peak_ms', 'P_arrival_ms', 'S2S_arrival_ms', 'first_bump_ratio', ...
        'near_field_start_ms', 'near_field_end_ms', 'snr', 'crosstalk', 'polarity_vote', 'polarity_margin'}];
body = [num2cell([res.f, res.fMeasured, res.LL, 1e6 * res.Ts, res.Vs(:, 2), res.Vs(:, 1), res.Vs(:, 4), ...
        zeros(n, 1)]), res.quality, num2cell([res.rxPeak_ms, res.rxPeakNorm, res.txPeak_ms, NaN(n, 1), ...
        res.s2s_ms, res.bump, res.nfStart_ms, res.nfEnd_ms, res.snr, double(res.crosstalk), res.vote, res.margin])];
writecell(nanToEmpty([hdr; body]), file, 'Sheet', 'Summary');
% waveforms and cross-correlations on one grid (time from each transmitter start)
dtc = min([sw.dt]);
span = min(arrayfun(@(k) R{k}.signals.t(end) - R{k}.transmitter.tStart, 1:n));   % covered by every record: no empty cells
tg = (0:dtc:span).';
W = 1e3 * tg;  wh = {'time_ms'};
for k = 1:n
    s = R{k}.signals;  tk = s.t - R{k}.transmitter.tStart;
    W = [W, interp1(tk, s.tx, tg), interp1(tk, s.rxRaw, tg), interp1(tk, s.rxFiltered, tg)];        %#ok<AGROW>
    wh = [wh, {sprintf('tx_%gkHz_V', res.f(k)), sprintf('rx_%gkHz_V', res.f(k)), ...
               sprintf('rx_filtered_%gkHz_V', res.f(k))}];                                          %#ok<AGROW>
end
writecell(wh, file, 'Sheet', 'Waveforms', 'Range', 'A1');
writematrix(W, file, 'Sheet', 'Waveforms', 'Range', 'A2');
lagMax = max(res.rxPeak_ms / 1e3 + 1.1 ./ (1e3 * res.f));
lg = (-0.05 * lagMax:dtc:lagMax).';
Cc = 1e3 * lg;  ch = {'lag_ms'};
for k = 1:n
    Cc = [Cc, interp1(R{k}.cc.tl, R{k}.cc.c, lg)];                                                  %#ok<AGROW>
    ch = [ch, {sprintf('cc_%gkHz', res.f(k))}];                                                     %#ok<AGROW>
end
writecell(ch, file, 'Sheet', 'CrossCorrelation', 'Range', 'A1');
writematrix(Cc, file, 'Sheet', 'CrossCorrelation', 'Range', 'A2');
testF = [];  if ~isempty(cfg.testFrequency), testF = cfg.testFrequency; end
par = {'item', 'value', 'note';
    'DATA TYPE', 'MEASURED', 'analysed with the BE_TravelTime_V6 methods by BE_SweepToWorkbook';
    'source', source, 'measured sweep workbook';
    'L_mm', 1e3 * cfg.L, 'travel length tip to tip';
    'Tc_us', 1e6 * cfg.Tc, 'system time delay';
    'ref_frequency_kHz', testF, 'test frequency (empty: set in BE_CompareSweeps)';
    'waveform_columns', 3, 'per frequency in Waveforms: tx, rx, rx as analysed (same: no filter)';
    'receiver_polarity', pol, polBasis;
    'filter', cfg.filterType, 'data supplied filtered';
    'frequency_basis', cfg.frequencyBasis, 'f_kHz: nominal (column titles) or measured transmitter';
    'reported_method', 'P2P', 'peak to peak; cross-correlation computed independently (Ts_CC_us, Vs_CC_m_s)';
    'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'BE_SweepToWorkbook'};
writecell(nanToEmpty(par), file, 'Sheet', 'Parameters');
end

function C = nanToEmpty(C)
for k = 1:numel(C)
    if isnumeric(C{k}) && (isempty(C{k}) || (isscalar(C{k}) && isnan(C{k}))), C{k} = ''; end
end
end

function s = cellText(c)
% text of a spreadsheet cell; '' for an empty cell (readcell gives <missing>)
s = '';
if ischar(c), s = c;
elseif isstring(c) && isscalar(c) && ~ismissing(c), s = char(c);
elseif (isnumeric(c) || islogical(c)) && isscalar(c) && ~isnan(c), s = num2str(c);
end
end

function v = cellNum(c)
% number from a spreadsheet cell: numeric, numeric text, or empty/missing -> NaN
if isnumeric(c) && isscalar(c), v = double(c);
elseif ischar(c) || isstring(c), v = str2double(c);
else, v = NaN;
end
end

% =========================================================================
%        ANALYSIS FUNCTIONS COPIED UNCHANGED FROM BE_TravelTime_V6
% =========================================================================
function T = analyseTransmitter(t, x)
N   = numel(x);
dt  = t(2) - t(1);
x0  = x - median(x);
A0  = max(abs(x0));
if A0 == 0, error('BE:txShape', 'The transmitter record is flat.'); end
iBig = find(abs(x0) > 0.2 * A0, 1);
% baseline: walk back down the flank to 2 % of the amplitude, then step back
% as far again as half the 2-20 % rise time, so no flank samples are included
k2 = iBig;  while k2 > 1 && abs(x0(k2)) > 0.02 * A0, k2 = k2 - 1; end
nb = k2 - max(5, ceil(0.5 * (iBig - k2)));
if nb < 10 && k2 - 1 >= 10
    nb = k2 - 1;                      % short pre-trigger: everything below the 2 % level
    warning('BE:pretrigger', ['Short pre-trigger on the transmitter: its baseline includes the ' ...
        'first part of the rise (below 2 %% of the amplitude). Record more pre-trigger signal.']);
end
if nb < 10
    error('BE:pretrigger', ['The transmitter pulse starts at the very beginning of the record ' ...
        '(fewer than 10 baseline samples). Record more pre-trigger signal.']);
end
T.baseline = median(x(1:nb));
xb = x - T.baseline;
T.noise = robustStd(xb(1:nb));
s   = sign(xb(iBig));                 % polarity of the first transmitter lobe
T.sign = s;
z   = s * xb;                         % first lobe positive
A   = max(z(iBig:min(N, iBig + round(N/4))));

% --- lobe boundaries. The top of the first lobe is the maximum before the trace is
%     clearly negative, so noise or quantisation steps on the flank cannot stop
%     the search early; zero-valued samples are skipped
iDeep = iBig + find(z(iBig+1:end) < -0.2 * A, 1);                       % well into the 2nd lobe
if isempty(iDeep)
    error('BE:txShape', 'The transmitter has no negative lobe: not a single-period sine pulse.');
end
[~, j] = max(z(iBig:iDeep));  iPk = iBig + j - 1;                       % top of first lobe
seg  = find(z(1:iPk) <= 0, 1, 'last');  if isempty(seg), seg = 1; end   % last baseline sample
iMid = iDeep;  while iMid > iPk && z(iMid) <= 0, iMid = iMid - 1; end   % last positive sample
iNeg = iMid + find(z(iMid+1:end) < 0, 1);                               % first negative sample
iEnd = iDeep + find(z(iDeep+1:end) >= -0.05 * A, 1);                    % back near the baseline
if isempty(iEnd), iEnd = N; end
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
if ~(T.tStart < T.tMid && T.tMid < T.tEnd)
    error('BE:txShape', 'Transmitter start, mid and end crossings are out of order: not a sine pulse.');
end

% --- frequency estimates
T.f.fullPeriod  = 1 / (T.tEnd - T.tStart);        % one complete sine period
T.f.halfPeriod1 = 1 / (2 * (T.tMid - T.tStart));
T.f.halfPeriod2 = 1 / (2 * (T.tEnd - T.tMid));
T.f.peakTrough  = 1 / (2 * (T.tTrough - T.tPeak));
nfft = fftLength(N, 16);
X = abs(fft(xb, nfft));  fa = (0:nfft-1).' / nfft / dt;
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

function [y, F] = filterReceiver(yr, fs, f0, opts)
F.type = opts.filterType;
if isempty(opts.filterBand), F.band = opts.filterBandFactor * f0; else, F.band = opts.filterBand(:).'; end
F.band(2) = min(F.band(2), 0.45 * fs);
if F.band(1) >= F.band(2)
    error('BE:opt', 'Filter band %.4g-%.4g Hz is empty after limiting it to 0.45 x sampling rate.', F.band);
end
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
        if ~(exist('butter', 'file') && exist('filtfilt', 'file') && exist('zp2sos', 'file'))
            error('BE:toolbox', 'opts.filterType = ''butter'' needs the Signal Processing Toolbox.');
        end
        % second-order sections: the [b,a] form is numerically unreliable at the
        % very low normalised cut-offs typical here (kHz signals, MHz sampling)
        [zz, pp, kk] = butter(opts.butterOrder, F.band / (fs/2), 'bandpass');
        [sos, g] = zp2sos(zz, pp, kk);
        y = filtfilt(sos, g, yr);
        zi = exp(-1i * 2*pi * F.fAxis / fs);           % z^-1 on the frequency axis
        h = g * ones(size(zi));
        for k = 1:size(sos, 1)
            h = h .* (sos(k,1) + sos(k,2)*zi + sos(k,3)*zi.^2) ./ (sos(k,4) + sos(k,5)*zi + sos(k,6)*zi.^2);
        end
        F.H = abs(h).^2;                               % forward-backward magnitude
end
end

function X = crosstalkCheck(t, x, ys, T, F, opts)
% electrical pick-up: receiver activity while the transmitter is still active,
% with the shape of the transmitter (or of its derivative, capacitive coupling)
X.window = [T.tStart, T.tEnd + 0.1 * T.period];
k = t >= X.window(1) & t <= X.window(2);
X.amp = max(abs(ys(k)));
X.corr = max(abs([ncorr(ys(k), x(k)), ncorr(ys(k), gradient(x(k)))]));
X.detected = X.amp > opts.noiseK * F.noiseSmooth && X.corr > 0.7;
if isfield(opts, 'skipCrosstalk') && opts.skipCrosstalk    % model signals: an early near field is not crosstalk
    X.detected = false;
end
X.minTravelTimeHint = X.window(2) - T.tStart;
if X.detected && opts.minTravelTime < X.minTravelTimeHint
    warning('BE:crosstalk', ['The receiver shows electrical crosstalk while the transmitter is active ' ...
        '(%.3g mV, correlation %.2f with the transmitter). Picks inside it are marked [CHECK]. If the ' ...
        'true arrival is later, set opts.minTravelTime = %.0fe-6 (s).'], 1e3*X.amp, X.corr, ...
        ceil(1e6 * X.minTravelTimeHint));
end
end

function P = pickReceiver(t, y, yRaw, ys, T, F, opts)
N = numel(y);  dt = t(2) - t(1);  s = T.sign;
z = s * y;  zs = s * ys;
P.tPeak1 = NaN; P.aPeak1 = NaN; P.tArrival = NaN;
P.tTrough1 = NaN; P.aTrough1 = NaN; P.fPeakTrough = NaN;
P.tNearField = NaN; P.aNearField = NaN; P.tFilterDip = NaN; P.tFirstDev = NaN;
P.ok = false;  P.snr = NaN;  P.fSpec = NaN;  P.env = envAnalytic(y);

tMin = T.tStart + opts.minTravelTime;
tMax = t(end);
if ~isempty(opts.maxTravelTime), tMax = min(tMax, T.tStart + opts.maxTravelTime); end
win = find(t >= tMin & t <= tMax);
if numel(win) < 10
    warning('BE:window', 'The search window (minTravelTime to maxTravelTime) holds fewer than 10 samples.');
    return
end
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

if isempty(iMx)
    P.ok = false;
else
    i1 = iMx(1);
    % first-peak lobe; it ends where the trace goes clearly negative (beyond the
    % noise band), so noise wiggles around zero do not cut it short
    lo = i1;  while lo > 1 && z(lo-1) > 0, lo = lo - 1; end
    hi = i1;  while hi < N && z(hi+1) > -thrNoise, hi = hi + 1; end
    [P.tPeak1, a] = refineExtremum(t, z, lo, hi, +1);  P.aPeak1 = s * a;
    % Start to Start: baseline (zero) crossing that opens this lobe (D8295 §10.1.2)
    P.tArrival = crossTime(t, z, lo - 1);
    % first trough after the first peak (opposite lobe, same noise band)
    lo2 = hi + 1;  hi2 = lo2;  while hi2 < N && z(hi2+1) < thrNoise, hi2 = hi2 + 1; end
    if lo2 < N && min(z(lo2:hi2)) < -thrNoise
        [P.tTrough1, a2] = refineExtremum(t, z, lo2, hi2, -1);  P.aTrough1 = s * a2;
        P.fPeakTrough = 1 / (2 * (P.tTrough1 - P.tPeak1));
    end
    % near-field excursion: largest opposite-sign extremum before the first lobe.
    % It must also be present in the smoothed raw trace; a dip seen only in the
    % filtered trace is filter ringing, not near field
    nf = iMn(iMn < lo & z(iMn) < -thrNoise);
    if ~isempty(nf)
        [~, j] = min(z(nf));  k = nf(j);
        if zs(k) < -opts.noiseK * F.noiseSmooth
            P.tNearField = t(k);  P.aNearField = s * z(k);
        else
            P.tFilterDip = t(k);
        end
    end
end
% first sustained deflection beyond the noise band (near-field onset), on the
% smoothed raw trace: the band-pass smears energy far ahead of an arrival
nSus = max(3, round(0.05 * T.period / dt));
ca = [0; cumsum(abs(zs) > opts.noiseK * F.noiseSmooth)];
runLen = ca(nSus+1:end) - ca(1:end-nSus);                    % runLen(k) = number above in k:k+nSus-1
kLast = min(numel(runLen), win(end) - nSus + 1);
if kLast >= win(1)
    k = find(runLen(win(1):kLast) == nSus, 1);
    if ~isempty(k), P.tFirstDev = t(win(1) + k - 1); end
end
% dominant receiver frequency: same estimator as T.f.spectralPeak (unfiltered)
seg = zeros(N, 1);  seg(win) = yRaw(win);
nfft = fftLength(N, 16);
Y = abs(fft(seg, nfft));  fa = (0:nfft-1).' / nfft / dt;
half = 2:floor(nfft/2);  [~, im] = max(Y(half));
P.fSpec = fa(half(im));
end

function C = crossCorr(x, y, dt, T, opts, useEnvelope)
if useEnvelope, a = envAnalytic(x); b = envAnalytic(y); else, a = x; b = y; end
a = a - mean(a);  b = b - mean(b);
N = numel(a);  nfft = 2^nextpow2(2*N);
c = real(ifft(fft(b, nfft) .* conj(fft(a, nfft))));          % c(k) = sum b(n+k) a(n)
c = [c(end-N+2:end); c(1:N)];  lags = (-(N-1):(N-1)).';
c = c / max(eps, sqrt(sum(a.^2) * sum(b.^2)));                % normalised coefficient
tl = lags * dt;
lagMax = (N-1)*dt;
if ~isempty(opts.maxTravelTime), lagMax = opts.maxTravelTime; end
ok = tl >= opts.minTravelTime & tl <= lagMax;
C.c = c;  C.tl = tl;  C.envelope = useEnvelope;
C.lag = NaN;  C.peak = NaN;  C.ok = false;  C.secondLag = NaN;  C.secondPeak = NaN;
C.tShiftStart = NaN;
idx = find(ok);
if isempty(idx), return; end
[pk, j] = max(c(idx));  k = idx(j);
lag = tl(k);
% a maximum on the edge of the lag window is not a peak: the real one lies outside
atEdge = k == idx(1) || k == idx(end);
if ~atEdge && c(k) >= c(k-1) && c(k) >= c(k+1)               % parabolic refinement
    den = c(k-1) - 2*c(k) + c(k+1);
    if den < 0, lag = lag + 0.5 * (c(k-1) - c(k+1)) / den * dt; end
end
C.lag = lag;  C.peak = pk;
C.ok = pk > 0 && ~atEdge;
if ~useEnvelope
    % runner-up peak: a second CC peak close in height means the pick is ambiguous
    d = diff(c);  loc = find([false; d(1:end-1) > 0 & d(2:end) <= 0; false] & ok);
    loc(abs(tl(loc) - tl(k)) < 0.5 * T.period) = [];          % ignore ripples on the main peak
    if ~isempty(loc)
        [C.secondPeak, j2] = max(c(loc)); C.secondLag = tl(loc(j2));
    end
    if C.secondPeak > 0.8 * pk
        warning('BE:ccAmbiguous', ['Cross-correlation has a second peak at %.1f us that is %.0f %% ' ...
            'of the maximum; the CC pick may be cycle-skipped.'], 1e6*C.secondLag, 100*C.secondPeak/pk);
    end
end
C.tShiftStart = T.tStart + lag;
end

function S = crossSpectrum(x, y, fs, f0, F)
N = numel(x);  nfft = fftLength(N, 8);
X = fft(x, nfft);  Y = fft(y, nfft);
f = (0:nfft-1).' * fs / nfft;
G = Y .* conj(X);
half = (1:floor(nfft/2)).';
band = [max(0.5*f0, F.band(1)), min(1.5*f0, F.band(2))];
m = half(f(half) >= band(1) & f(half) <= band(2));
m = m(abs(X(m)) >= 0.3 * max(abs(X(half))));                 % keep frequencies the tx excites
phAll = unwrap(angle(G(half)));
S.f = f(half);  S.Gmag = abs(G(half));  S.phase = phAll;
S.X = abs(X(half));  S.Y = abs(Y(half));
S.band = [NaN NaN];  S.tau = NaN;  S.R2 = NaN;  S.ok = false;
S.fFit = [];  S.phFit = [];  S.phModel = [];
if numel(m) < 3, return; end
S.band = [f(m(1)) f(m(end))];
ph = phAll(m);
w  = abs(G(m));  w = w / max(eps, max(w));
Aw = [ones(numel(m),1) 2*pi*f(m)] .* sqrt(w);
p  = Aw \ (ph .* sqrt(w));                                    % weighted LS: ph = p1 + p2*2*pi*f
S.tau = -p(2);
res = ph - (p(1) + p(2)*2*pi*f(m));
S.R2 = 1 - sum(w .* res.^2) / sum(w .* (ph - sum(w.*ph)/sum(w)).^2);
S.ok = S.tau > 0 && S.R2 > 0.9;
S.fFit = f(m);  S.phFit = ph;  S.phModel = p(1) + p(2)*2*pi*f(m);
end

function M = flagRows(M, mask, why)
% mark the selected methods [CHECK] and say why in their note
for k = find(mask(:).')
    if isnan(M(k).Ts), continue; end
    M(k).quality = 'check';
    M(k).note = [M(k).note '; ' why];
end
end

function M = addVelocity(M, opts, f0, fRx)
L = [];
if ~isempty(opts.L), L = opts.L;
elseif ~isempty(opts.H_i) && ~isempty(opts.H_b), L = opts.H_i - opts.dH_c - opts.H_b;   % D8295 §7.3
end
if ~isempty(L) && L <= 0
    warning('BE:geometry', 'Travel length L = H_i - dH_c - H_b = %.4g m is not positive; Vs not computed.', L);
    L = [];
end
for k = 1:numel(M)
    Ts = M(k).Ts;
    M(k).Ts_us = 1e6 * Ts;
    M(k).wavelengthsInPath_tx = f0 * (Ts - opts.Tc);   % L/lambda = f*(Ts - Tc), independent of L
    M(k).wavelengthsInPath_rx = fRx * (Ts - opts.Tc);  % same with the rx peak-to-trough frequency
    M(k).Vs = NaN;  M(k).Gmax_MPa = NaN;
    if ~isempty(L) && Ts - opts.Tc > 0
        M(k).Vs = L / (Ts - opts.Tc);                    % D8295 Eq. 1
        if ~isempty(opts.rho), M(k).Gmax_MPa = opts.rho * M(k).Vs^2 / 1e6; end   % Eq. 3
    end
end
end

function r = mrow(name, tag, basis, Ts, ok, note)
if ok && ~isnan(Ts) && Ts > 0, q = 'ok'; else, q = 'check'; end
r = struct('name', name, 'tag', tag, 'basis', basis, 'Ts', Ts, 'quality', q, 'note', note);
end

function m = movingMean(v, n)
% centred moving average over n samples, shortened at the ends (as movmean),
% computed from a cumulative sum: O(N) time and memory for any window length
v = v(:);  N = numel(v);  i = (1:N).';
kb = floor(n/2);  kf = n - 1 - kb;
lo = max(1, i - kb);  hi = min(N, i + kf);
mu = mean(v);  c = [0; cumsum(v - mu)];
m = (c(hi + 1) - c(lo)) ./ (hi - lo + 1) + mu;
end

function n = fftLength(N, factor)
% zero-padded FFT length for spectral peaks: factor x N, but not beyond 2^20
% points unless the record itself is longer
n = 2^nextpow2(max(N, min(factor * N, 2^20)));
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
    dt = t(2) - t(1);  t0 = t(use(1));
    p = polyfit((t(use) - t0) / dt, z(use), 1);
    if p(1) ~= 0, tr = t0 - dt * p(2) / p(1); return; end
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
    dt = t(2) - t(1);
    tt = (t(lo:hi) - t(j)) / dt;                      % time in samples: well conditioned
    p = polyfit(tt, z(lo:hi), 2);
    tv = -p(2) / (2*p(1));
    if sgn*p(1) < 0 && tv >= tt(1) && tv <= tt(end)
        tp = t(j) + dt * tv;  ap = polyval(p, tv);  return;
    end
    tp = mean(t(lo:hi));  ap = z(j);  return;            % flat (clipped/quantised) top
end
tp = t(j);  ap = z(j);
end

function r = ncorr(a, b)
% normalised correlation coefficient at zero lag
a = a(:) - mean(a);  b = b(:) - mean(b);
r = sum(a .* b) / max(eps, sqrt(sum(a.^2) * sum(b.^2)));
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

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function ts = methodTs(R, tag)
k = strcmp({R.methods.tag}, tag);
ts = NaN;  if any(k), ts = R.methods(find(k, 1)).Ts; end
end
