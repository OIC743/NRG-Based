%% =========================================================================
%  BENDER-ELEMENT SHEAR-WAVE TRAVEL-TIME ANALYSIS  (ASTM D8295-19)
%  BE_TravelTime_V6  |  variants and near-field calibration sweep
%  =========================================================================
%
%  HOW TO RUN: edit the USER SETTINGS block below and run the script (F5,
%  or type BE_TravelTime_V6). Leave txFile / rxFile empty to be asked for
%  each file in turn: first the TRANSMITTER, then the RECEIVER.
%  The recorded signals are analysed first (run 1). A dialog then asks what
%  to do next:
%     Change the transmitter frequency   (e.g. 10 kHz recorded -> 4 kHz)
%     Set the travel time                (e.g. Start to Start = 500 us)
%     Calibration: near-field frequency sweep (4-40 kHz)
%     Reset both to the recorded signals
%     RUN the analysis with these settings  -> new calculations and figures
%     Done                                  -> summary table of all runs
%  Results are left in the workspace: R (last run) and Rall (all runs).
%  Variants can also be listed in opts.variations; they then run without
%  dialogs (reproducible, e.g. for a parametric study).
%
%  CHANGING THE FREQUENCY (simulation): a single-cycle sine at the new
%  frequency replaces the transmitter, with the recorded start time,
%  amplitude and polarity. The receiver signal is PREDICTED with the
%  transfer function measured from the recording,
%        H(f) = Y(f) X*(f) / (|X(f)|^2 + eps),   Y_new = H X_new
%  i.e. soil + benders + electronics are treated as one linear,
%  time-invariant system. The receiver frequency follows from H.
%  LIMIT: the recording only shows how the system responds at frequencies
%  the recorded pulse contains. A single-cycle sine at f has no energy at
%  0, 2f, 3f, ... and little far outside 0-2f, so a 10 kHz record cannot
%  predict a 30 kHz test. "Coverage" = share of the new pulse's energy at
%  frequencies where the recorded spectrum is at least 10 % of its maximum.
%  Below opts.simMinCoverage the frequency is refused; below
%  opts.simGoodCoverage every result of that run is marked [CHECK].
%
%  CALIBRATION (near-field frequency sweep, SIMULATED): the received signal
%  at each frequency (default 4, 8, 15, 20, 30, 40 kHz) is built with
%  Stokes' solution for a point force in an infinite elastic medium
%  (e.g. Aki & Richards, Quantitative Seismology, ch. 4), displacement
%  parallel to the force at a receiver on the axis normal to it:
%        y(t) = g(t - Ts) - k * (1/Ts^2) * integral_{Tp}^{Ts} tau g(t - tau) dtau
%  Ts = L/Vs, Tp = L/Vp, k = opts.calNearFieldScale (1 = Stokes). The second
%  term is the near field: opposite sign, arriving from the P-wave time on,
%  relatively larger the smaller L/lambda is - strongest at low frequency,
%  fading at high frequency - and produced whether or not the recording
%  shows one. g is the received far-field pulse: with opts.calShape =
%  'recorded' it is YOUR received signal from its arrival on (its ringing,
%  its shape; any recorded near field left out), scaled in time to each
%  frequency, and the transmitter is your recorded pulse scaled the same
%  way; recorded pre-trigger noise is added. The near field acts on the
%  received signal only - it does not change the transmitted pulse.
%  The received pulse starts at the far-field travel time and its rise to the
%  first peak is matched to the transmitter's (the rest of the recorded
%  pulse, its ringing, is kept), so that without the near field T_pp would
%  not depend on frequency: the frequency dependence comes from the near field.
%  'ideal' uses a single-cycle sine for both, without noise.
%  WAVE VARIATION: a smooth random wave in the signal band (0.5-2 x f),
%  following the envelope of the received signal, is added from the
%  far-field arrival on, different at each frequency, zero at and around
%  the first peak (its time and height, so T_pp, are unchanged). It is
%  scaled so that neither its largest value (against the first peak) nor
%  its RMS (against the received waves) exceeds opts.calVariation
%  (default 5 %). Reproducible through opts.calSeed. The figures show the receiver after the same
%  zero-phase band-pass as the analysis; the workbook keeps both.
%  TRAVEL TIMES: the model is fitted to a peak-to-peak time at a reference
%  frequency (default: run 1). The dialog then lists the model T_pp for
%  every frequency; keep it or type your own value, and the received signal
%  of that frequency is shifted to reproduce it. Entered values are marked
%  (* in the figure, ENTERED in the report, user_entered in the workbook).
%  Output: stacked-waveform figure, stacked normalised cross-correlation
%  figure, Vs / near-field trend figure, Excel workbook (Summary, Waveforms,
%  CrossCorrelation, Parameters) from which the figures can be
%  recreated (opts.recreateFromExcel). Everything is labelled SIMULATED.
%  LIMITS: elastic, non-dispersive medium; receiver output proportional to
%  displacement; the recorded pulse is assumed to keep its shape in cycles
%  at other frequencies (a real bender's own resonance does not move);
%  damping and specimen boundaries are not modelled.
%
%  SETTING THE TRAVEL TIME: the receiver signal is shifted in time (exact
%  sub-sample FFT delay) so that the chosen reference method returns the
%  requested travel time; the other methods move by the same amount.
%  Shifting the receiver later is the same as shifting the transmitter
%  earlier. Samples entering the record are filled with recorded
%  pre-trigger noise. The waveform itself is kept: attenuation, dispersion
%  and the size of the near field, which would change with path length in
%  a real test, are not modelled, and crosstalk (if any) moves with it.
%
%  INPUT FILES: oscilloscope CSV exports with a key/value header followed by
%  a "Waveform Data" block (e.g. GW Instek GDS "Fast" mode: one integer ADC
%  count per line; "Detail" mode time,value pairs are also accepted).
%  Both files must come from the SAME acquisition (same trigger, same time
%  base), e.g. CH1 = transmitter, CH2 = receiver.
%
%  TRAVEL-TIME METHODS (times are measured from the transmitter):
%     1  Start to Start            ASTM D8295-19 §10.1.2
%     2  Peak to Peak              ASTM D8295-19 §10.1.1
%     3  Trough to Trough          consistency check on the 2nd lobe (not in D8295)
%     4  Cross-correlation         time domain, raw signal shape (D8295 §10.2: "other method")
%     5  Envelope cross-correl.    Hilbert envelopes                (D8295 §10.2)
%     6  Cross-power spectrum      phase slope / group delay        (D8295 §10.2)
%     7  First deflection          near-field onset, informational (lower bound)
%     8  Manual pick (optional)    opts.manualPick = true
%  D8295 §10.2 allows methods other than 1-2 only "provided they have been
%  shown to provide reliable results"; report which method you used (§12.3.11).
%
%  START TO START: transmitter start = straight line through the 5-30 % part
%  of its first rising flank, extrapolated to the baseline; receiver arrival
%  = baseline crossing of the filtered trace that opens the first peak lobe.
%  The zero-phase filter can move a SHARP receiver onset slightly earlier
%  (about 1.5 % of the transmitter period in tests on synthetic records);
%  compare with opts.filterType = 'none' when the onset looks abrupt.
%
%  CROSSTALK: electrical pick-up of the transmitter on the receiver (signal
%  in the receiver while the transmitter is still active, shaped like the
%  transmitter) is detected and reported. Picks that fall inside it are
%  marked [CHECK]; set opts.minTravelTime to skip it.
%
%  Shear-wave velocity / Gmax (D8295 Eq. 1-3) are computed only if you
%  supply the geometry (opts.H_i, opts.dH_c, opts.H_b, or opts.L directly),
%  the time-delay correction opts.Tc (§8.1) and the density opts.rho.
%
%  Requires base MATLAB only (R2016b or later for local functions in a
%  script; written for R2025b). opts.filterType = 'butter' needs the Signal
%  Processing Toolbox.
%  =========================================================================

%% ============================ USER SETTINGS ==============================
txFile = '';                    % transmitter CSV  ('' -> file dialog)
rxFile = '';                    % receiver CSV     ('' -> file dialog)

opts = struct();
% --- receiver signal processing
opts.rxPolarity       = +1;     % -1 inverts the receiver trace (D8295 §7.4.1)
opts.filterType       = 'fft';  % 'fft' (zero-phase, no toolbox) | 'butter' (filtfilt) | 'none'
opts.filterBand       = [];     % [fLow fHigh] Hz; [] -> filterBandFactor * f_tx
opts.filterBandFactor = [0.25 4];
opts.butterOrder      = 4;      % for 'butter' (applied forward-backward => zero phase)
% --- picking
opts.minTravelTime    = 0;      % s; nothing earlier is picked (use it to skip crosstalk)
opts.maxTravelTime    = [];     % s; [] -> to the end of the record
opts.ampFrac          = 0.25;   % rx peak must reach this fraction of max |rx| in the window
opts.noiseK           = 4;      % detection threshold, multiples of pre-trigger noise
opts.minSNR           = 10;     % below this receiver peak SNR every result is marked [CHECK]
opts.manualPick       = false;  % true -> click picks on a figure after each run
% --- geometry and material (leave [] to skip Vs and Gmax)
opts.L                = [];     % m, travel length tip-to-tip (overrides H_i, dH_c, H_b)
opts.H_i              = [];     % m, initial specimen height       (D8295 Eq. 1)
opts.dH_c             = 0;      % m, height change at reading       (D8295 Eq. 1)
opts.H_b              = [];     % m, total bender protrusion        (D8295 Eq. 1)
opts.Tc               = 0;      % s, time-delay correction           (D8295 §8.1)
opts.rho              = [];     % kg/m^3, total density at reading   (D8295 Eq. 2)
% --- frequency / travel-time variants
opts.interactive      = true;   % after each run ask what to do next (dialogs)
opts.variations       = struct('f', {}, 'Ts', {}, 'refMethod', {});
                                % runs done first, without dialogs. f in Hz ([] = recorded),
                                % Ts in s ([] = as measured), refMethod 'S2S','P2P','T2T',
                                % 'CC','ECC','CPS' or 'FD'. Example:
                                % struct('f', {4e3, 12e3}, 'Ts', {[], 500e-6}, 'refMethod', {'S2S', 'S2S'})
opts.simMinCoverage   = 0.5;    % new frequency refused below this coverage
opts.simGoodCoverage  = 0.9;    % below this coverage all results of the run are marked [CHECK]
% --- calibration: near-field frequency sweep (SIMULATED, Stokes point-force model)
opts.calibration      = false;  % true -> run the sweep after run 1 without asking
opts.calFrequencies   = [4 8 15 20 30 40] * 1e3;   % Hz
opts.calRefFrequency  = [];     % Hz; frequency of the reference P2P time ([] = recorded f_tx)
opts.calRefTpp        = [];     % s; peak-to-peak travel time at that frequency ([] = run 1 value)
opts.calPoisson       = 0.3;    % Poisson's ratio of the medium -> Vp/Vs (used if calVp is [])
opts.calVp            = [];     % m/s, P-wave velocity (needs the travel length L)
opts.calShape         = 'recorded';  % 'recorded' (your pulses scaled to each frequency) | 'ideal' (sine)
opts.calNearFieldScale = 1.1;   % multiplies the near-field term (1 = Stokes solution;
                                % 1.1 = near-field dip 10 % deeper than Stokes)
opts.calVariation     = 0.05;   % random wave variation, largest value as a fraction of the
                                % first-peak height (0 = none); first peak itself unchanged
opts.calSeed          = 1;      % seed of the random variation (same seed = same figures)
opts.calTpp           = [];     % s, T_pp per frequency of calFrequencies (NaN = model value);
                                % with interactive = true they are asked for in a dialog
opts.recreateFromExcel = '';    % path of a calibration .xlsx: only redraw its figures and stop
% --- oscilloscope and output
opts.countsPerDiv     = 25;     % ADC counts per vertical division ("Fast" CSV). UNVERIFIED for
                                % your scope model - affects amplitudes only, never travel times.
opts.saveOutputs      = true;   % one sub-folder per run + all_runs.csv
opts.outputFolder     = '';     % '' -> folder "BE_results_<rx file name>" next to the rx file
opts.showFigures      = true;
%% =========================================================================

opts = defaultOptions(opts);

% ---- 0. Redraw a saved calibration (no analysis) ---------------------------
if ~isempty(opts.recreateFromExcel)
    cal = readCalibrationExcel(opts.recreateFromExcel);
    calFigs = plotCalibration(cal, opts);                                %#ok<NASGU>
    fprintf('Calibration figures redrawn from %s\n', opts.recreateFromExcel);
    return
end

% ---- 1. File selection: each file chosen separately ---------------------
filt = {'*.csv;*.CSV;*.txt', 'Oscilloscope export (*.csv, *.txt)'; '*.*', 'All files (*.*)'};
if isempty(txFile)
    [f, p] = uigetfile(filt, 'Select the TRANSMITTED signal file (e.g. *_1.CSV)');
    if isequal(f, 0), disp('No transmitter file selected - analysis cancelled.'); return; end
    txFile = fullfile(p, f);
end
if isempty(rxFile)
    [f, p] = uigetfile(filt, 'Select the RECEIVED signal file (e.g. *_2.CSV)', [fileparts(txFile) filesep]);
    if isequal(f, 0), disp('No receiver file selected - analysis cancelled.'); return; end
    rxFile = fullfile(p, f);
end
if ~isfile(txFile), error('BE:file', 'Transmitter file not found: %s', txFile); end
if ~isfile(rxFile), error('BE:file', 'Receiver file not found: %s', rxFile); end
if strcmpi(txFile, rxFile)
    error('BE:sameFile', 'Transmitter and receiver files are the same file.');
end

% ---- 2. Read both records -----------------------------------------------
TX = readScopeCSV(txFile, opts);
RX = readScopeCSV(rxFile, opts);
checkCompatible(TX, RX);
N   = min(numel(TX.v), numel(RX.v));
rec = struct('t', (0:N-1).' * TX.dt, 'x', TX.v(1:N), 'y', RX.v(1:N));   % s, V, V (raw)
src = sourceInfo(txFile, rxFile, TX, RX, opts);

% ---- 3. Run 1: the recorded signals --------------------------------------
R = analyseRecord(rec.t, rec.x, rec.y, src, opts, newSim(1), true);
Rrec = R;
Rall = {R};

% ---- 4. Variants listed in opts.variations (no dialogs) ------------------
for kv = 1:numel(opts.variations)
    v = opts.variations(kv);
    [Rk, msg] = runVariant(rec, Rrec, src, opts, v.f, v.Ts, v.refMethod, numel(Rall) + 1);
    if isempty(Rk)
        warning('BE:variant', 'Variation %d not run: %s', kv, msg);
    else
        R = Rk;  Rall{end+1} = Rk;                                      %#ok<SAGROW>
    end
end

% ---- 5. Calibration sweep requested in the settings ----------------------
cal = [];
if opts.calibration
    [cal, msg] = runCalibration(Rrec, src, opts, calibrationSettings(Rrec, opts));
    if isempty(cal), warning('BE:calibration', 'Calibration not run: %s', msg); end
end

% ---- 6. Variants and calibration chosen interactively --------------------
if opts.interactive
    pend = struct('f', [], 'Ts', [], 'refMethod', 'S2S');
    fRange = reliableRange(Rrec.transmitter, rec.t, opts);
    while true
        try
            act = askNextStep(pend, numel(Rall));
        catch err
            warning('BE:dialog', ['Dialogs are not available (%s). Set opts.interactive = false ' ...
                'and list the variants in opts.variations.'], err.message);
            break
        end
        switch act
            case 'freq'
                pend.f = askFrequency(pend.f, Rrec, fRange, opts);
            case 'ts'
                [pend.Ts, pend.refMethod] = askTravelTime(pend.Ts, pend.refMethod, R);
            case 'cal'
                cs = askCalibration(calibrationSettings(Rrec, opts), Rrec);
                if ~isempty(cs)
                    [calK, msg] = runCalibration(Rrec, src, opts, cs);
                    if isempty(calK)
                        uiwait(errordlg(msg, 'Calibration not run', 'modal'));
                    else
                        cal = calK;
                    end
                end
            case 'reset'
                pend.f = [];  pend.Ts = [];
            case 'run'
                if isempty(pend.f) && isempty(pend.Ts)
                    uiwait(msgbox(['Nothing is changed yet: set a frequency and/or a travel time ' ...
                        'first, or choose Done.'], 'Bender element analysis', 'modal'));
                    continue
                end
                [Rk, msg] = runVariant(rec, Rrec, src, opts, pend.f, pend.Ts, pend.refMethod, numel(Rall) + 1);
                if isempty(Rk)
                    uiwait(errordlg(msg, 'Variant not run', 'modal'));
                else
                    R = Rk;  Rall{end+1} = Rk;                              %#ok<SAGROW>
                end
            otherwise
                break
        end
    end
end

% ---- 7. Summary of all runs -----------------------------------------------
printRunSummary(Rall, 1);
if opts.saveOutputs
    writeRunSummary(Rall, baseFolder(src, opts));
end

% =========================================================================
%                      ANALYSIS OF ONE SIGNAL PAIR
% =========================================================================
function R = analyseRecord(t, x, yr, src, opts, sim, verbose)
% complete analysis of one transmitter / receiver pair. verbose = false is
% used for reference runs: no figures, report or files, and no warnings
if ~verbose
    ws = warning('off', 'all');
    restoreWarnings = onCleanup(@() warning(ws));                       %#ok<NASGU>
end
dt = t(2) - t(1);  fs = 1/dt;  N = numel(t);

% ---- transmitter: start, peaks, frequency
T = analyseTransmitter(t, x);
x = x - T.baseline;                  % baseline-free transmitter
f0 = T.f.primary;

% ---- receiver: offset removal and filtering
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
% lightly smoothed raw trace (centred moving average over 5 % of a period) for
% onset work: it keeps the noise down without the long reach of the band-pass
F.nSmooth = max(1, round(0.05 * T.period / dt));
ys = movingMean(yr, F.nSmooth);
% noise levels. A short pre-trigger holds few independent samples of band-limited
% noise, so its estimate can come out low: the filtered and smoothed values are
% never taken below what white noise of the raw level would give. The smoothed
% trace keeps the DC level, so the uncertainty of the offset removed above counts too
F.noiseRaw    = robustStd(yr(iPre));
F.noiseFilt   = max(robustStd(y(iPre)), F.noiseRaw * sqrt(mean(F.H.^2)));
F.noiseSmooth = max(robustStd(ys(iPre)), F.noiseRaw * sqrt(1/F.nSmooth + 1/nnz(iPre)));

% ---- crosstalk check and receiver picks
X = crosstalkCheck(t, x, ys, T, F, opts);
P = pickReceiver(t, y, yr, ys, T, F, opts);

% ---- travel times by every method
% every method needs a receiver signal clearly above the noise (opts.minSNR)
sigOK = P.snr >= opts.minSNR;
if ~sigOK && ~isnan(P.snr)
    warning('BE:weakSignal', ['Receiver peak SNR = %.1f is below opts.minSNR = %g: the signal may be ' ...
        'noise. All travel times are marked [CHECK].'], P.snr, opts.minSNR);
end
M = struct('name', {}, 'tag', {}, 'basis', {}, 'Ts', {}, 'quality', {}, 'note', {});
M(end+1) = mrow('Start to Start',     'S2S', 'ASTM D8295 §10.1.2', P.tArrival - T.tStart, P.ok && sigOK, ...
               'rx baseline crossing before 1st peak minus tx start');
M(end+1) = mrow('Peak to Peak',       'P2P', 'ASTM D8295 §10.1.1', P.tPeak1 - T.tPeak, P.ok && sigOK, ...
               '1st rx peak minus 1st tx peak');
M(end+1) = mrow('Trough to Trough',   'T2T', 'check (not in D8295)', P.tTrough1 - T.tTrough, ...
               P.ok && sigOK && ~isnan(P.tTrough1), '1st rx trough after the 1st peak minus tx trough');
C  = crossCorr(x, y, dt, T, opts, false);
M(end+1) = mrow('Cross-correlation',  'CC', 'D8295 §10.2 (other)', C.lag, C.ok && sigOK, ...
               sprintf('max normalised CC = %.3f', C.peak));
CE = crossCorr(x, y, dt, T, opts, true);
M(end+1) = mrow('Envelope cross-correlation', 'ECC', 'D8295 §10.2 (other)', CE.lag, CE.ok && sigOK, ...
               sprintf('max normalised CC of envelopes = %.3f', CE.peak));
S  = crossSpectrum(x, y, fs, f0, F);
M(end+1) = mrow('Cross-power spectrum', 'CPS', 'D8295 §10.2 (other)', S.tau, S.ok && sigOK, ...
               sprintf('phase-slope fit %.1f-%.1f kHz, R^2 = %.3f', S.band/1e3, S.R2));
M(end+1) = mrow('First deflection',   'FD', 'informational (near-field onset)', ...
               P.tFirstDev - T.tStart, ~isnan(P.tFirstDev) && sigOK, ...
               sprintf('first sustained |rx| > %g x noise (smoothed raw trace); lower bound, includes near field', ...
               opts.noiseK));
if ~sim.isSim && src.rxLevels < 20                       % picks on a staircase trace
    M = flagRows(M, ismember({M.tag}, {'S2S', 'P2P', 'T2T', 'FD'}), ...
        sprintf('receiver uses only %d ADC levels', src.rxLevels));
end

% ---- raw-signal cross-correlation as a filter-sensitivity check
Craw = crossCorr(x, yr, dt, T, opts, false);

% ---- figures
figs = gobjects(0);
info = figInfo(src, T, F, opts, sim);
if verbose
    figs(end+1) = plotOverview(t, x, yr, y, T, F, P, info, opts);
    figs(end+1) = plotS2S(t, x, yr, y, T, P, M(1), X, info);
    figs(end+1) = plotPeaks(t, x, yr, y, T, P, M(2), M(3), info);
    figs(end+1) = plotCC(t, x, y, C,  T, M(4), info, 'Cross-correlation of transmitter and receiver signals');
    figs(end+1) = plotCC(t, T.env, P.env, CE, T, M(5), info, 'Cross-correlation of signal envelopes');
    figs(end+1) = plotCPS(S, M(6), f0, info);
    if opts.manualPick                                   % D8295 Fig. 3 style, user clicks
        [tsMan, okMan] = manualPick(t, x, y, T, info);
        M(end+1) = mrow('Manual pick', 'MAN', 'user pick', tsMan, okMan, 'clicked tx point then rx point');
    end
end

% ---- window, crosstalk and simulation flags, velocity, Gmax, wavelength ratio
tsAll = [M.Ts];
tMaxTT = Inf;  if ~isempty(opts.maxTravelTime), tMaxTT = opts.maxTravelTime; end
M = flagRows(M, tsAll < opts.minTravelTime | tsAll > tMaxTT, 'outside the search window');
if X.detected
    M = flagRows(M, tsAll < X.window(2) - T.tStart, 'inside the crosstalk window');
end
if T.extraCycles                                         % envelope of a continuing wave has no feature
    M = flagRows(M, strcmp({M.tag}, 'ECC'), 'transmitter is not a single pulse');
end
if strcmp(sim.kind, 'variant') && ~isempty(sim.fNew)    % noise of a predicted receiver is not real noise
    M = flagRows(M, strcmp({M.tag}, 'FD'), ['simulated receiver: the first deflection depends on ' ...
        'the noise level, which the simulation does not reproduce']);
end
if sim.isSim && sim.coverage < opts.simGoodCoverage
    M = flagRows(M, true(1, numel(M)), sprintf(['simulated: only %.0f %% of the pulse energy ' ...
        'lies where the recording is informative'], 100 * sim.coverage));
end
M = addVelocity(M, opts, f0, P.fPeakTrough);
if verbose
    figs(end+1) = plotSummary(M, Craw, info, opts);
end
if sim.isSim && ~isempty(sim.TsTarget)
    sim.TsObtained = M(find(strcmp({M.tag}, sim.refMethod), 1)).Ts;
end

% ---- report
R = struct();
R.files     = src.files;
R.meta      = src.meta;
R.sim       = sim;
R.dt        = dt;
R.transmitter = T;
R.filter    = rmfield(F, {'H', 'fAxis'});
R.crosstalk = X;
R.picks     = rmfield(P, 'env');
R.cc        = C;  R.ccEnvelope = CE;  R.ccRaw = Craw;  R.crossSpectrum = S;
R.methods   = M;
R.table     = struct2table(rmfield(M, 'tag'));
R.options   = opts;
R.figures   = figs;
R.signals   = struct('t', t, 'tx', x, 'rxRaw', yr, 'rxFiltered', y);
if verbose
    printReport(R);
    if opts.saveOutputs
        R.outputFolder = saveOutputs(R, figs, runFolder(src, opts, sim));
    end
end
end

% =========================================================================
%                   FREQUENCY AND TRAVEL-TIME VARIANTS
% =========================================================================
function sim = newSim(runNo)
sim = struct('isSim', false, 'kind', 'recorded', 'runNo', runNo, 'label', 'recorded signals', 'fNew', [], ...
    'TsTarget', [], 'refMethod', '', 'coverage', NaN, 'shift', 0, 'TsRef', NaN, 'TsObtained', NaN);
end

function [R, msg] = runVariant(rec, Rrec, src, opts, fNew, TsTarget, refMethod, runNo)
% one variant of the recorded pair: new transmitter frequency (simulated),
% travel time set by a shift of the receiver, or both
R = [];  msg = '';
if isempty(refMethod), refMethod = 'S2S'; end
T0 = Rrec.transmitter;
t = rec.t;  dt = t(2) - t(1);
x = rec.x;
y = rec.y - mean(rec.y(t < T0.tStart));                  % raw receiver, offset removed
sim = newSim(runNo);
sim.isSim = true;  sim.kind = 'variant';
sim.fNew = fNew;  sim.TsTarget = TsTarget;  sim.refMethod = refMethod;
if isempty(fNew) && isempty(TsTarget)
    msg = 'neither a frequency nor a travel time is set';
    return
end

% ---- new transmitter frequency: synthesised pulse, receiver through H(f)
if ~isempty(fNew)
    [x, y, sim.coverage, msg] = simulateFrequency(t, T0, y, fNew, opts);
    if isempty(x), return; end
end
fTx = T0.f.primary;  if ~isempty(fNew), fTx = fNew; end

% ---- travel time: shift the receiver so that refMethod gives TsTarget
if ~isempty(TsTarget)
    if ~(TsTarget > 0)
        msg = 'the travel time must be positive';
        return
    end
    Rq = analyseRecord(t, x, y, src, opts, sim, false);
    tsRef = methodTs(Rq, refMethod);
    if isnan(tsRef)
        msg = sprintf(['%s gives no travel time on this signal pair, so the shift cannot be set ' ...
            'from it. Choose another reference method.'], refMethod);
        return
    end
    % room for the shifted arrival plus three periods; extend the record if needed
    tNeed = T0.tStart + max(TsTarget, tsRef) + 3 / fTx;
    fill = y(t < T0.tStart);
    if tNeed > t(end)
        nExt = ceil((tNeed - t(end)) / dt);
        x = [x; repmat(median(x(t < T0.tStart)), nExt, 1)];  % transmitter baseline
        y = [y; tileNoise(fill, nExt)];
        t = (0:numel(t) + nExt - 1).' * dt;
    end
    y0 = y;
    shift = TsTarget - tsRef;
    for it = 1:3                                         % the pick moves with the shift; check it
        y = shiftDelay(y0, shift, dt, fill);
        Rq = analyseRecord(t, x, y, src, opts, sim, false);
        got = methodTs(Rq, refMethod);
        if isnan(got) || abs(got - TsTarget) <= dt / 4, break; end
        shift = shift + (TsTarget - got);
    end
    sim.shift = shift;  sim.TsRef = tsRef;
end
sim.label = variantLabel(sim);
R = analyseRecord(t, x, y, src, opts, sim, true);
if ~isempty(TsTarget)
    if ~(abs(R.sim.TsObtained - TsTarget) <= max(dt, 0.002 * TsTarget))
        warning('BE:shift', '%s returns %.2f us, not the requested %.2f us.', refMethod, ...
            1e6 * R.sim.TsObtained, 1e6 * TsTarget);
    end
end
end

function [xNew, yNew, cov, msg] = simulateFrequency(t, T0, y, fNew, opts)
% single-cycle sine at fNew (recorded start, amplitude and polarity) and the
% receiver predicted with the measured transfer function H = Y X* / (|X|^2 + eps)
xNew = [];  yNew = [];  msg = '';
dt = t(2) - t(1);  N = numel(t);
cov = NaN;
if ~(isnumeric(fNew) && isscalar(fNew) && fNew > 0 && fNew < 0.45 / dt)
    msg = sprintf('the frequency must be between 0 and %.4g kHz (0.45 x sampling rate)', 0.45e-3 / dt);
    return
end
if T0.tStart + 1.5 / fNew > t(end)
    msg = sprintf('the record is too short for a pulse at %.4g kHz', fNew / 1e3);
    return
end
nfft = 2^nextpow2(2 * N);
X = fft(T0.x, nfft);
fAx = (0:nfft/2).' / (nfft * dt);
informative = abs(X(1:nfft/2+1)) >= 0.1 * max(abs(X));
cov = pulseCoverage(fAx, informative, fNew);
if cov < opts.simMinCoverage
    rng = reliableRange(T0, t, opts);
    msg = sprintf(['%.4g kHz is outside what this recording can predict: only %.0f %% of the ' ...
        'pulse energy lies where the recorded pulse has energy (minimum %.0f %%). Usable range: ' ...
        '%.3g-%.3g kHz (all results reliable %.3g-%.3g kHz).'], fNew / 1e3, 100 * cov, ...
        100 * opts.simMinCoverage, rng.min / 1e3, rng.good / 1e3);
    return
end
tau = t - T0.tStart;
xNew = abs(T0.aPeak) * T0.sign * sin(2*pi*fNew*tau) .* (tau >= 0 & tau <= 1/fNew);
Y  = fft(y, nfft);
Xn = fft(xNew, nfft);
reg = (0.05 * max(abs(X)))^2;                          % regularisation of the division
yy = real(ifft(Y .* conj(X) ./ (abs(X).^2 + reg) .* Xn));
yNew = yy(1:N);
end

function c = pulseCoverage(f, informative, fNew)
% share of the energy of a single-cycle sine at fNew that lies at frequencies
% where the recorded transmitter spectrum is informative. Continuous-time
% spectrum: |X(w)| = w0 * 2 |sin(w T/2)| / |w0^2 - w^2|, T = 1/fNew (T/2 at w0)
w = 2*pi*f;  w0 = 2*pi*fNew;  Tn = 1 / fNew;
mag = w0 * 2 * abs(sin(w * Tn / 2)) ./ abs(w0^2 - w.^2);
near = abs(w - w0) < 1e-6 * w0;
mag(near) = Tn / 2;
E = mag.^2;
c = sum(E(informative)) / sum(E);
end

function rng = reliableRange(T0, t, opts)
% frequency ranges (around the recorded one) with coverage >= simGoodCoverage
% (rng.good) and >= simMinCoverage (rng.min)
dt = t(2) - t(1);  nfft = 2^nextpow2(2 * numel(t));
X = abs(fft(T0.x, nfft));
fAx = (0:nfft/2).' / (nfft * dt);
informative = X(1:nfft/2+1) >= 0.1 * max(X);
fc = T0.f.primary * logspace(log10(0.05), log10(8), 200);
fc = fc(fc < 0.45 / dt);
cv = arrayfun(@(fn) pulseCoverage(fAx, informative, fn), fc);
rng.good = contiguousRange(fc, cv >= opts.simGoodCoverage, T0.f.primary);
rng.min  = contiguousRange(fc, cv >= opts.simMinCoverage, T0.f.primary);
rng.f = fc;  rng.coverage = cv;
end

function r = contiguousRange(fc, ok, f0)
[~, k] = min(abs(fc - f0));
r = [NaN NaN];
if ~ok(k), return; end
lo = k;  while lo > 1 && ok(lo-1), lo = lo - 1; end
hi = k;  while hi < numel(fc) && ok(hi+1), hi = hi + 1; end
r = [fc(lo) fc(hi)];
end

function y2 = shiftDelay(y, d, dt, fill)
% delay y by d seconds (d < 0: earlier). Whole samples by indexing, the
% remaining fraction by an FFT phase ramp on a mirrored copy (no edge jump).
% Samples that enter the record are taken from 'fill' (pre-trigger noise)
N = numel(y);  n = round(d / dt);  fr = d / dt - n;
y2 = zeros(N, 1);
if n >= 0
    m = min(n, N);
    y2(m+1:N) = y(1:N-m);  y2(1:m) = tileNoise(fill, m);
else
    m = min(-n, N);
    y2(1:N-m) = y(m+1:N);  y2(N-m+1:N) = tileNoise(fill, m);
end
if fr ~= 0
    z = [y2; flipud(y2)];  L = numel(z);
    k = (0:L-1).';  k(k > L/2) = k(k > L/2) - L;      % signed frequency index
    z = real(ifft(fft(z) .* exp(-1i * 2*pi * k * fr / L)));
    y2 = z(1:N);
end
end

function v = tileNoise(fill, n)
% n samples of recorded noise (repeated as needed); zeros if none is available
fill = fill(:);
if n <= 0, v = zeros(0, 1); return; end
if isempty(fill), v = zeros(n, 1); return; end
v = repmat(fill - mean(fill), ceil(n / numel(fill)), 1);
v = v(1:n);
end

function ts = methodTs(R, tag)
k = strcmp({R.methods.tag}, tag);
ts = NaN;  if any(k), ts = R.methods(find(k, 1)).Ts; end
end

function s = variantLabel(sim)
parts = {};
if ~isempty(sim.fNew), parts{end+1} = sprintf('tx frequency %.3f kHz (simulated)', sim.fNew / 1e3); end
if ~isempty(sim.TsTarget)
    parts{end+1} = sprintf('%s set to %.1f us (rx shifted %+.1f us)', sim.refMethod, ...
        1e6 * sim.TsTarget, 1e6 * sim.shift);
end
s = strjoin(parts, ', ');
end

% =========================================================================
%           CALIBRATION: NEAR-FIELD FREQUENCY SWEEP (SIMULATED)
% =========================================================================
function cs = calibrationSettings(Rrec, opts)
% calibration inputs from the settings; run-1 values as defaults
T0 = Rrec.transmitter;
[cs.f, order] = sort(opts.calFrequencies(:).');
cs.Tpp = NaN(size(cs.f));                                % per-frequency T_pp, NaN = model value
if ~isempty(opts.calTpp), cs.Tpp = opts.calTpp(order); end
cs.refF = opts.calRefFrequency;
if isempty(cs.refF), cs.refF = T0.f.primary; end
cs.refTpp = opts.calRefTpp;
if isempty(cs.refTpp), cs.refTpp = methodTs(Rrec, 'P2P'); end      % NaN if run 1 has none
cs.L = travelLength(opts);
cs.poisson = opts.calPoisson;
cs.Vp = opts.calVp;
cs.shape = opts.calShape;
cs.nfScale = opts.calNearFieldScale;
cs.askTpp = opts.interactive;
cs.variation = opts.calVariation;
cs.seed = opts.calSeed;
end

function L = travelLength(opts)
% tip-to-tip travel length from the settings, [] if not given (D8295 §7.3)
L = [];
if ~isempty(opts.L), L = opts.L;
elseif ~isempty(opts.H_i) && ~isempty(opts.H_b), L = opts.H_i - opts.dH_c - opts.H_b;
end
if ~isempty(L) && ~(L > 0), L = []; end
end

function cs = askCalibration(cs, Rrec)
% dialog for the calibration inputs; [] on Cancel
def = {strjoin(arrayfun(@(v) sprintf('%g', v / 1e3), cs.f, 'UniformOutput', false), ' '), ...
       sprintf('%.4g', cs.refF / 1e3), numText(1e6 * cs.refTpp, '%.2f'), numText(1e3 * cs.L, '%.3f'), ...
       sprintf('%.3g', cs.poisson), numText(cs.Vp, '%.0f'), sprintf('%g', cs.nfScale), cs.shape, ...
       sprintf('%g', 100 * cs.variation)};
prompts = {'Frequencies of the sweep (kHz, separated by spaces):', ...
    sprintf('Reference frequency (kHz); recorded f_tx = %.3f kHz:', Rrec.transmitter.f.primary / 1e3), ...
    'Peak-to-peak travel time at the reference frequency (us); calibrates the model:', ...
    'Travel length L tip to tip (mm), for Vs (empty: travel times only):', ...
    'Poisson''s ratio of the medium (sets Vp/Vs; not used if Vp is given):', ...
    'P-wave velocity Vp (m/s), optional (needs L):', ...
    'Near-field scale (1 = Stokes solution; recorded in the outputs):', ...
    'Waveform shape: recorded (your signals, scaled to each frequency) or ideal (sine):', ...
    'Random wave variation (% of the first-peak height, 0 = none; first peak unchanged):'};
while true
    a = inputdlg(prompts, 'Calibration: near-field frequency sweep (simulated)', [1 75], def);
    if isempty(a), cs = []; return; end
    def = a(:).';
    [c, err] = parseCalibration(a, cs);
    if isempty(err), cs = c; return; end
    uiwait(errordlg(err, 'Calibration', 'modal'));
end
end

function [cs, err] = parseCalibration(a, cs)
err = '';
f = sscanf(regexprep(a{1}, '[,;]', ' '), '%f').' * 1e3;
refF = str2double(a{2}) * 1e3;
refTpp = str2double(a{3}) * 1e-6;
L = [];  if ~isempty(strtrim(a{4})), L = str2double(a{4}) * 1e-3; end
nu = str2double(a{5});
Vp = [];  if ~isempty(strtrim(a{6})), Vp = str2double(a{6}); end
nfs = str2double(a{7});
shape = lower(strtrim(a{8}));
vari = str2double(a{9}) / 100;
if isempty(f) || any(~isfinite(f)) || any(f <= 0), err = 'Enter the sweep frequencies in kHz, e.g. 4 8 15 20 30 40.';
elseif ~(refF > 0), err = 'Enter a positive reference frequency (kHz).';
elseif ~(refTpp > 0), err = 'Enter the peak-to-peak travel time at the reference frequency (us).';
elseif ~isempty(L) && ~(L > 0), err = 'The travel length must be positive (mm), or left empty.';
elseif ~(nu >= 0 && nu < 0.5), err = 'Poisson''s ratio must be between 0 and 0.5.';
elseif ~isempty(Vp) && ~(Vp > 0), err = 'Vp must be positive (m/s), or left empty.';
elseif ~isempty(Vp) && isempty(L), err = 'Vp needs the travel length L (to get Vp/Vs).';
elseif ~(nfs >= 0), err = 'The near-field scale must be zero or positive (1 = Stokes solution).';
elseif ~ismember(shape, {'recorded', 'ideal'}), err = 'Waveform shape must be "recorded" or "ideal".';
elseif ~(vari >= 0 && vari <= 0.5), err = 'The random wave variation must be between 0 and 50 %.';
end
if isempty(err)
    fNew = sort(unique(f));
    if ~isequal(fNew, cs.f), cs.Tpp = NaN(size(fNew)); end   % entered times belong to the old list
    cs.f = fNew;  cs.refF = refF;  cs.refTpp = refTpp;
    cs.L = L;  cs.poisson = nu;  cs.Vp = Vp;  cs.nfScale = nfs;  cs.shape = shape;  cs.variation = vari;
end
end

function Tpp = askCalibrationTpp(f, TppModel, Tpp)
% one field per frequency, pre-filled with the model value (or the value
% entered before). Returns NaN where the model value is kept; [] on Cancel
n = numel(f);
modelTxt = arrayfun(@(k) sprintf('%.2f', 1e6 * TppModel(k)), 1:n, 'UniformOutput', false);
def = modelTxt;
for k = 1:n
    if ~isnan(Tpp(k)), def{k} = sprintf('%.2f', 1e6 * Tpp(k)); end
end
prompts = arrayfun(@(k) sprintf('%g kHz   (model: %s us)', f(k) / 1e3, modelTxt{k}), 1:n, ...
    'UniformOutput', false);
prompts{1} = sprintf(['Peak-to-peak travel time for each frequency (us).\nKeep the model value or ' ...
    'enter your own. Entered values are marked as such\nin the figures, the report and the workbook.\n\n%s'], ...
    prompts{1});
while true
    a = inputdlg(prompts, 'Calibration: travel time per frequency', [1 45], def);
    if isempty(a), Tpp = []; return; end
    a = cellfun(@strtrim, a(:).', 'UniformOutput', false);
    v = str2double(a) * 1e-6;
    if any(~(v > 0))
        uiwait(errordlg('Every travel time must be a positive number of microseconds.', 'Travel time', 'modal'));
        def = a;  continue
    end
    v(strcmp(a, modelTxt)) = NaN;                       % unchanged: keep the model value
    Tpp = v;
    return
end
end

function s = numText(v, fmt)
s = '';
if ~isempty(v) && isfinite(v), s = sprintf(fmt, v); end
end

function r = vpOverVs(cs, TsFF)
% Vp/Vs of the model: from Vp and the far-field velocity L/TsFF, else from Poisson's ratio
if ~isempty(cs.Vp)
    r = cs.Vp / (cs.L / TsFF);
else
    r = sqrt(2 * (1 - cs.poisson) / (1 - 2 * cs.poisson));
end
end

function [B, msg] = calibrationBase(Rrec, shape)
% waveform shapes the sweep is built from, as functions of cycles u:
%   xFun(u): transmitter pulse, u = 0 at its start
%   gFun(u): received far-field pulse, u = 0 at its arrival, first peak = +1.
%            Its rise from the arrival to the first peak is matched to the
%            transmitter's (time warp of that part only; the rest of the
%            recorded pulse is kept in cycles), so the far-field pulse starts
%            at Ts and peaks one transmitter rise later: without the near
%            field T_pp = Ts at every frequency
% 'recorded': taken from run 1 (receiver from its arrival on, so any recorded
% near field or crosstalk is left out) plus the recorded pre-trigger noise;
% 'ideal': single-cycle sine, no noise
msg = '';
T0 = Rrec.transmitter;  f0 = T0.f.primary;
B.shape = shape;  B.A = abs(T0.aPeak) * T0.sign;  B.noise = [];  B.dtNoise = [];
sine = @(u) sin(2*pi*u) .* (u >= 0 & u <= 1);
if strcmp(shape, 'ideal')
    B.xFun = sine;  B.gFun = sine;  B.rxAmp = 0.05;
    return
end
S = Rrec.signals;  t = S.t;  dt = t(2) - t(1);  P = Rrec.picks;
if isnan(P.tArrival) || isnan(P.aPeak1)
    msg = ['run 1 has no receiver arrival, so the recorded receiver shape cannot be used; ' ...
        'choose the ideal shape'];
    B = [];
    return
end
% transmitter: recorded pulse from a quarter cycle before its start to 1.4 cycles
u = (t - T0.tStart) * f0;
k = u >= -0.25 & u <= 1.4;
ux = u(k);  xs = S.tx(k) / B.A;
xs = xs .* min(1, (ux + 0.25) / 0.1) .* min(1, (1.4 - ux) / 0.1);       % fade in / out
B.xFun = @(v) interp1(ux, xs, v, 'linear', 0);
% receiver: filtered trace, first peak scaled to +1, from its onset on. The
% onset is found like the transmitter start: a line through the steadily
% rising 20-60 % part of the first lobe, extended to zero; below 20 % the
% pulse follows that line, so whatever precedes the rise (a recorded near
% field, filter ringing) is left out
z = T0.sign * S.rxFiltered / (T0.sign * P.aPeak1);
[~, iPk] = min(abs(t - P.tPeak1));
iLo = iPk;                                               % start of the monotonic rise above 20 %
while iLo > 1 && z(iLo - 1) > 0.2 && z(iLo - 1) < z(iLo), iLo = iLo - 1; end
use = (iLo:iPk).';  use = use(z(use) <= 0.6);
tOn = P.tArrival;  i20 = iLo;
if numel(use) >= 3
    pl = polyfit((t(use) - t(iLo)) / dt, z(use), 1);
    if pl(1) > 0, tOn = min(t(iLo), t(iLo) - dt * pl(2) / pl(1)); end
end
k = t >= t(i20);
vg = [0; (t(k) - tOn) * f0];  gs = [0; z(k)];           % straight from zero at the onset to the 20 % point
gs = gs .* min(1, (vg(end) - vg) / 0.5);                 % no step at the end of the record
uPkRx = (P.tPeak1 - tOn) * f0;                           % recorded rise, cycles
uPkTx = (T0.tPeak - T0.tStart) * f0;                     % transmitter rise, cycles (about 0.25)
if ~(uPkRx > 0 && uPkTx > 0), uPkRx = 1; uPkTx = 1; end % no usable rise: no warp
warp = @(w) (w <= uPkTx) .* w * (uPkRx / uPkTx) + (w > uPkTx) .* (uPkRx + w - uPkTx);
B.gFun = @(w) interp1(vg, gs, warp(w), 'linear', 0) .* (w >= 0);
B.rxAmp = abs(P.aPeak1);
pre = S.rxRaw(t < T0.tStart);
B.noise = pre - mean(pre);  B.dtNoise = dt;
end

function n = noiseOn(B, t, offset)
% recorded pre-trigger noise laid over the time axis t (repeated as needed,
% started 'offset' samples in so that traces do not share the same noise)
n = zeros(size(t));
if isempty(B.noise), return; end
m = numel(B.noise);
need = ceil((t(end) - t(1)) / B.dtNoise) + 2;
idx = mod((0:need-1).' + offset, m) + 1;
tn = t(1) + (0:need-1).' * B.dtNoise;
n = interp1(tn, B.noise(idx), t, 'linear', 0);
end

function [x, y, part] = calibrationPair(t, tStart, f, TsFF, ratio, B, nfScale, noiseOffset)
% transmitter and receiver at frequency f. Receiver = Stokes' point-force
% solution (infinite elastic medium, displacement parallel to the force,
% receiver on the axis normal to it) with the received far-field pulse g:
%   y(t) = g(t - Ts) - nfScale * (1/Ts^2) * integral_{Tp}^{Ts} tau g(t - tau) dtau
% Ts = far-field S travel time (onset; the far-field peak follows one
% transmitter rise later, so far-field T_pp = Ts), Tp =
% Ts / (Vp/Vs). The near-field term goes through the receiver exactly like
% the far field (linear receiver), so g may be the recorded received pulse.
% Plus recorded noise.
dt = t(2) - t(1);  N = numel(t);
x   = B.A * B.xFun((t - tStart) * f);
g   = B.gFun((t - tStart) * f);                          % pulse referred to the source time
far = B.gFun((t - tStart - TsFF) * f);
Tp  = TsFF / ratio;
tau = (0:ceil(TsFF / dt)).' * dt;
w   = tau .* (tau >= Tp & tau <= TsFF);
nfft = 2^nextpow2(N + numel(w));
nf  = real(ifft(fft(g, nfft) .* fft(w, nfft)));
near = nfScale * nf(1:N) * dt / TsFF^2;
sc  = sign(B.A) * B.rxAmp / max(abs(far));
y   = sc * (far - near) + noiseOn(B, t, noiseOffset);
part = struct('far', sc * far, 'near', -sc * near, 'Tp', Tp);
end

function e = waveVariation(t, f, tOn, tPk, amp, frac, seed, ySig)
% random, smooth change of the received waves: band-limited (0.5-2 x f)
% random signal, weighted by the envelope of the received signal ySig (so
% it is a share of the local wave, not noise where the signal has died
% out), from the far-field onset tOn on, and zero at and around the first
% peak tPk (weight 1 - exp(-((t - tPk)/(T/4))^4): value and slope zero
% there, so the peak keeps its time and height). Scaled so that BOTH its
% largest value <= frac x first-peak height amp AND its RMS <= frac x RMS
% of ySig after the onset
N = numel(t);  dt = t(2) - t(1);  T = 1 / f;
r = randomNormals(seed, N);
nfft = 2^nextpow2(N);
fa = (0:nfft-1).' / (nfft * dt);  fa = min(fa, 1 / dt - fa);   % |frequency| of each FFT bin
e = real(ifft(fft(r, nfft) .* double(fa >= 0.5 * f & fa <= 2 * f)));
e = e(1:N) / max(eps, max(abs(e(1:N))));
ramp = min(max((t - tOn) / (0.25 * T), 0), 1);
e = e .* envAnalytic(ySig) .* (1 - exp(-((t - tPk) / (0.25 * T)).^4)) .* (0.5 - 0.5 * cos(pi * ramp));
after = t >= tOn;
rmsSig = sqrt(mean(ySig(after).^2));  rmsE = sqrt(mean(e(after).^2));
e = e * frac * min(amp / max(eps, max(abs(e))), rmsSig / max(eps, rmsE));
end

function r = randomNormals(seed, N)
% N standard normal numbers from their own generator (the global one is left alone)
s = RandStream('mt19937ar', 'Seed', seed);
r = randn(s, N, 1);
end

function sim = calSim(f)
sim = newSim(0);
sim.isSim = true;  sim.kind = 'calibration';  sim.fNew = f;
sim.label = sprintf('calibration %.3f kHz (near-field model)', f / 1e3);
end

function [TsFF, got] = fitTpp(target, TsFF, gen, f, analyse, tol)
% far-field travel time for which the simulated T_pp at f equals target
got = NaN;
for it = 1:40
    [x, y] = gen(f, TsFF);
    got = methodTs(analyse(x, y, f), 'P2P');
    if isnan(got) || abs(got - target) <= tol, return; end
    TsFF = TsFF + (target - got);
    if TsFF <= 0, got = NaN; return; end
end
end

function [cal, msg] = runCalibration(Rrec, src, opts, cs)
% near-field frequency sweep: fit the model to the reference T_pp, show the
% model T_pp per frequency (and take the user's values where entered), then
% build, analyse, plot and save every frequency
cal = [];  msg = '';
if ~(cs.refTpp > 0)
    msg = 'run 1 gives no peak-to-peak travel time: enter one for the reference frequency';
    return
end
if ~isempty(cs.Vp) && isempty(cs.L)
    msg = 'a P-wave velocity needs the travel length L';
    return
end
[B, msg] = calibrationBase(Rrec, cs.shape);
if isempty(B), return; end
T0 = Rrec.transmitter;
fAll = unique([cs.f, cs.refF]);
dt = min(Rrec.dt, 1 / (100 * max(fAll)));                % at least 100 samples per period
tStart = T0.tStart;
tLong = max([cs.refTpp, cs.Tpp(isfinite(cs.Tpp))]);
t = (0:ceil((tStart + 1.6 * tLong + 4 / min(fAll)) / dt)).' * dt;
o = opts;                                                % analysis of model signals
o.skipCrosstalk = true;  o.minTravelTime = 0;  o.maxTravelTime = [];
o.rxPolarity = 1;  o.manualPick = false;
tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
tol = max(dt / 2, 1e-4 * cs.refTpp);
analyse = @(x, y, f) analyseRecord(t, x, y, src, o, calSim(f), false);
ratioOf = @(TsFF) vpOverVs(cs, TsFF);
gen = @(f, TsFF) calibrationPair(t, tStart, f, TsFF, ratioOf(TsFF), B, cs.nfScale, 0);

% ---- far-field travel time reproducing T_pp at the reference frequency
if ~(ratioOf(cs.refTpp) > 1)
    msg = sprintf('Vp = %.0f m/s is not larger than Vs', cs.Vp);
    return
end
[TsFF0, got] = fitTpp(cs.refTpp, cs.refTpp, gen, cs.refF, analyse, tol);
if isnan(got) || abs(got - cs.refTpp) > 10 * tol
    msg = sprintf('the model cannot reproduce T_pp = %.2f us at %.3f kHz', 1e6 * cs.refTpp, cs.refF / 1e3);
    return
end

% ---- model T_pp at every frequency, then the user's values where entered
n = numel(cs.f);
TppModel = NaN(1, n);
for k = 1:n
    [x, y] = gen(cs.f(k), TsFF0);
    TppModel(k) = methodTs(analyse(x, y, cs.f(k)), 'P2P');
end
Tpp = cs.Tpp;
if cs.askTpp
    Tpp = askCalibrationTpp(cs.f, TppModel, Tpp);
    if isempty(Tpp), msg = 'cancelled'; cal = []; return; end
end
userSet = isfinite(Tpp);

% ---- the sweep
N = numel(t);
cal = struct('f', cs.f(:), 'tms', 1e3 * (t - tStart), 'tx', zeros(N, n), 'rx', zeros(N, n), ...
    'Ts', NaN(n, 7), 'quality', {repmat({''}, n, 7)}, 'tags', {tags}, ...
    'TppModel', TppModel(:), 'TppEntered', Tpp(:), 'userSet', userSet(:), ...
    'TsFFk', NaN(n, 1), 'ratioK', NaN(n, 1), ...
    'VsPP', NaN(n, 1), 'VsS2S', NaN(n, 1), 'LL', NaN(n, 1), 'LLff', NaN(n, 1), ...
    'nfModel', NaN(n, 1), 'bump', NaN(n, 1), 'tPeakRx_ms', NaN(n, 1), 'aPeakRxNorm', NaN(n, 1), ...
    'tPeakTx_ms', NaN(n, 1), 'tP_ms', NaN(n, 1), 'tS2S_ms', NaN(n, 1), ...
    'TsFF', TsFF0, 'ratio', ratioOf(TsFF0), 'refF', cs.refF, 'refTpp', cs.refTpp, ...
    'L', NaN, 'Tc', opts.Tc, 'VsFF', NaN, 'poisson', cs.poisson, 'Vp', NaN, ...
    'shape', cs.shape, 'nfScale', cs.nfScale, 'variation', cs.variation, 'seed', cs.seed, ...
    'rxf', zeros(N, n), 'varChange', zeros(n, 1), 'varRms', zeros(n, 1), 'dPPvar', zeros(n, 1), ...
    'ccLag_ms', [], 'cc', [], ...
    'source', sprintf('Tx: %s | Rx: %s', src.txName, src.rxName), ...
    'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
if ~isempty(cs.L), cal.L = cs.L;  cal.VsFF = cs.L / TsFF0; end
if ~isempty(cs.Vp), cal.Vp = cs.Vp; end
for k = 1:n
    TsFF = TsFF0;
    if userSet(k)                                        % far-field time giving the entered T_pp
        [TsFF, got] = fitTpp(Tpp(k), TsFF0 + (Tpp(k) - TppModel(k)), gen, cs.f(k), analyse, tol);
        if isnan(got) || abs(got - Tpp(k)) > 10 * tol
            msg = sprintf('T_pp = %.2f us at %g kHz cannot be reproduced by the model', 1e6 * Tpp(k), cs.f(k) / 1e3);
            cal = [];
            return
        end
    end
    noiseOffset = round(numel(t) / 7) * k;               % different noise stretch per trace
    [x, y, part] = calibrationPair(t, tStart, cs.f(k), TsFF, ratioOf(TsFF), B, cs.nfScale, noiseOffset);
    R = analyse(x, y, cs.f(k));
    if cs.variation > 0                                  % random wave variation, first peak kept
        P0 = R.picks;
        ySig = part.far + part.near;                     % received signal without the recorded noise
        e = waveVariation(t, cs.f(k), tStart + TsFF, P0.tPeak1, abs(P0.aPeak1), cs.variation, cs.seed + k, ySig);
        after = t >= tStart + TsFF;
        cal.varChange(k) = max(abs(e)) / abs(P0.aPeak1);                  % largest change / first peak
        cal.varRms(k) = sqrt(mean(e(after).^2) / mean(ySig(after).^2));   % RMS change of the waves
        y = y + e;
        R1 = analyse(x, y, cs.f(k));
        cal.dPPvar(k) = methodTs(R1, 'P2P') - methodTs(R, 'P2P');
        R = R1;
    end
    for j = 1:7
        m = R.methods(strcmp({R.methods.tag}, tags{j}));
        cal.Ts(k, j) = m.Ts;  cal.quality{k, j} = m.quality;
    end
    tPP = cal.Ts(k, 2);  tSS = cal.Ts(k, 1);
    cal.TsFFk(k) = TsFF;  cal.ratioK(k) = ratioOf(TsFF);
    cal.LL(k) = cs.f(k) * (tPP - opts.Tc);               % L/lambda with the apparent velocity
    cal.LLff(k) = cs.f(k) * TsFF;
    if ~isempty(cs.L)
        cal.VsPP(k)  = cs.L / (tPP - opts.Tc);
        cal.VsS2S(k) = cs.L / (tSS - opts.Tc);
    end
    P = R.picks;
    cal.tx(:, k) = x;  cal.rx(:, k) = y;  cal.rxf(:, k) = R.signals.rxFiltered;
    if k == 1, cal.ccLag_ms = 1e3 * R.cc.tl;  cal.cc = zeros(numel(R.cc.tl), n); end
    cal.cc(:, k) = R.cc.c;
    cal.nfModel(k) = max(abs(part.near)) / max(abs(part.far));
    z = T0.sign * (y - noiseOn(B, t, noiseOffset));      % first opposite-sign bump before the 1st peak
    pre = t >= tStart & t < P.tPeak1;
    cal.bump(k) = max([0; -z(pre)]) / (T0.sign * P.aPeak1);
    cal.tPeakRx_ms(k) = 1e3 * (P.tPeak1 - tStart);
    cal.aPeakRxNorm(k) = P.aPeak1 / max(abs(y));
    cal.tPeakTx_ms(k) = 1e3 * (R.transmitter.tPeak - tStart);
    cal.tP_ms(k) = 1e3 * part.Tp;
    cal.tS2S_ms(k) = 1e3 * (P.tArrival - tStart);
end

% cross-correlation kept over the lags the figure shows
keep = cal.ccLag_ms >= -0.05 * max(cal.tPeakRx_ms) & cal.ccLag_ms <= max(cal.tPeakRx_ms + 1.1e3 ./ cal.f);
cal.ccLag_ms = cal.ccLag_ms(keep);  cal.cc = cal.cc(keep, :);

% ---- report, figures, Excel
printCalibration(cal, 1);
figs = plotCalibration(cal, opts);
if opts.saveOutputs
    folder = fullfile(baseFolder(src, opts), ['calibration_' datestr(now, 'yyyymmdd_HHMMSS')]);
    if ~exist(folder, 'dir')
        [okDir, m] = mkdir(folder);
        if ~okDir, error('BE:save', 'Cannot create the output folder %s: %s', folder, m); end
    end
    cal.excelFile = fullfile(folder, 'calibration_nearfield.xlsx');
    writeCalibrationExcel(cal, cal.excelFile);
    for k = 1:numel(figs)
        nm = regexprep(get(figs(k), 'Name'), '[^\w]+', '_');
        try
            exportgraphics(figs(k), fullfile(folder, sprintf('%02d_%s.png', k, nm)), 'Resolution', 300);
        catch err
            warning('BE:save', 'Figure "%s" not saved: %s', get(figs(k), 'Name'), err.message);
        end
    end
    fid = openOrFail(fullfile(folder, 'calibration_report.txt'));  printCalibration(cal, fid);  fclose(fid);
    save(fullfile(folder, 'calibration.mat'), 'cal');
    fprintf('Calibration saved in: %s\n', folder);
end
end

function printCalibration(cal, fid)
n = numel(cal.f);
fprintf(fid, '\n=== CALIBRATION: near-field frequency sweep - SIMULATED (Stokes point-force model) ===\n');
fprintf(fid, '%s\n', cal.source);
fprintf(fid, ['Model fitted so that T_pp = %.2f us at %.3f kHz: far-field Ts = %.2f us, Vp/Vs = %.2f, ' ...
    'near-field scale %g.\nWaveforms: %s. Not measured data.\n'], 1e6 * cal.refTpp, cal.refF / 1e3, ...
    1e6 * cal.TsFF, cal.ratio, cal.nfScale, shapeText(cal.shape));
if ~isnan(cal.VsFF)
    fprintf(fid, 'Travel length L = %.2f mm -> model Vs = %.2f m/s (Tc = %.2f us)\n', 1e3 * cal.L, cal.VsFF, 1e6 * cal.Tc);
end
fprintf(fid, '%7s %7s %10s %10s %9s %9s %9s %8s %8s\n', 'f kHz', 'L/lam', 'T_pp model', 'T_pp used', ...
    'source', 'Vs_pp', 'T_ss us', 'NF/FF', 'bump');
for k = 1:n
    fprintf(fid, '%7.2f %7.2f %10.2f %10.2f %9s %9.2f %9.2f %8.3f %8.3f\n', cal.f(k) / 1e3, cal.LL(k), ...
        1e6 * cal.TppModel(k), 1e6 * cal.Ts(k, 2), ternary(cal.userSet(k), 'ENTERED', 'model'), ...
        cal.VsPP(k), 1e6 * cal.Ts(k, 1), cal.nfModel(k), cal.bump(k));
end
if n >= 2                                                % what the sweep shows (computed, not imposed)
    dPP = abs(diff(cal.Ts(:, 2)));
    [dMin, kMin] = min(dPP);
    fprintf(fid, 'Near field (model amplitude ratio) decreases with frequency over the whole sweep: %s\n', ...
        ternary(all(diff(cal.nfModel) < 0), 'yes', 'no'));
    fprintf(fid, 'Smallest T_pp change between neighbouring frequencies: %.3g-%.3g kHz (%.2f us)\n', ...
        cal.f(kMin) / 1e3, cal.f(kMin + 1) / 1e3, 1e6 * dMin);
end
if any(cal.userSet)
    fprintf(fid, 'ENTERED = travel time typed in by the user; the waveform was shifted to reproduce it.\n');
end
if cal.variation > 0
    fprintf(fid, ['Random wave variation (seed %d, limit %g %%): largest change %.1f-%.1f %% of the first ' ...
        'peak; RMS change of the waves %.1f-%.1f %%; T_pp change from it at most %.3f us.\n'], ...
        cal.seed, 100 * cal.variation, 100 * min(cal.varChange), 100 * max(cal.varChange), ...
        100 * min(cal.varRms), 100 * max(cal.varRms), 1e6 * max(abs(cal.dPPvar)));
end
fprintf(fid, 'NF/FF = peak near-field term / peak far-field term; bump = first opposite-sign excursion / first peak.\n\n');
end

function s = shapeText(shape)
if strcmp(shape, 'recorded')
    s = 'recorded transmitter and receiver pulses scaled to each frequency (receiver rise matched to the transmitter), recorded noise';
else
    s = 'ideal single-cycle sine, no noise';
end
end

function figs = plotCalibration(cal, opts)
vis = 'on';  if ~opts.showFigures, vis = 'off'; end
figs = plotCalibrationStack(cal, vis);
if ~isempty(cal.cc), figs(end+1) = plotCalibrationCC(cal, vis); end
figs(end+1) = plotCalibrationTrend(cal, vis);
end

function fig = plotCalibrationStack(cal, vis)
% stacked transmitter / receiver signals, one trace per frequency
fig = figure('Name', 'Calibration - near-field sweep (simulated)', 'Color', 'w', 'Visible', vis, ...
    'Units', 'pixels', 'Position', [60 40 900 980]);
ax = axes(fig);  hold(ax, 'on');
n = numel(cal.f);  cols = lines(n);  amp = 0.42;
orange = [0.95 0.55 0.10];  magenta = [0.85 0 0.55];
xmax = min(cal.tms(end), max(cal.tPeakRx_ms + 1.1e3 ./ cal.f));   % end of the slowest received pulse
rxShow = cal.rx;                                         % receiver after the analysis band-pass
if ~isempty(cal.rxf) && any(cal.rxf(:)), rxShow = cal.rxf; end
for k = 1:n
    off = k - 1;
    sx = amp / max(eps, max(abs(cal.tx(:, k))));
    sy = amp / max(eps, max(abs(rxShow(:, k))));
    plot(ax, [0 xmax], [off off], ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);
    plot(ax, cal.tms, off + sx * cal.tx(:, k), '--', 'Color', [0.30 0.30 0.30], 'LineWidth', 0.9);
    plot(ax, cal.tms, off + sy * rxShow(:, k), '-', 'Color', cols(k, :), 'LineWidth', 1.3);
    yPk = off + amp * cal.aPeakRxNorm(k) * max(abs(cal.rx(:, k))) / max(eps, max(abs(rxShow(:, k))));
    if isnan(cal.VsPP(k)), lab = sprintf('T_{pp} = %.1f \\mus', 1e6 * cal.Ts(k, 2));
    else,                  lab = sprintf('V_s = %.2f (m/s)', cal.VsPP(k));
    end
    if cal.userSet(k), lab = [lab ' *']; end                                         %#ok<AGROW>
    if isfinite(cal.tPeakRx_ms(k)) && isfinite(yPk)
        text(ax, cal.tPeakRx_ms(k) + 0.02 * xmax, yPk + 0.05, lab, 'Color', cols(k, :), 'FontSize', 9);
    end
    text(ax, 0.985 * xmax, off - 0.24, sprintf('L/\\lambda = %.2f', cal.LL(k)), ...
        'HorizontalAlignment', 'right', 'FontSize', 9);
    text(ax, 1.01 * xmax, off, sprintf('%g\n(kHz)', cal.f(k) / 1e3), 'Color', cols(k, :), ...
        'FontWeight', 'bold', 'FontSize', 10, 'Clipping', 'off');
end
% first receiver peaks (peak-to-peak picks) joined across frequencies
okPk = isfinite(cal.tPeakRx_ms) & isfinite(cal.aPeakRxNorm);
plot(ax, cal.tPeakRx_ms(okPk), find(okPk) - 1 + amp * cal.aPeakRxNorm(okPk), '-o', 'Color', orange, ...
    'MarkerFaceColor', orange, 'MarkerSize', 4, 'LineWidth', 1.3);
% T_pp arrow on the trace nearest the reference frequency
[~, kr] = min(abs(cal.f - cal.refF));
if isfinite(cal.tPeakTx_ms(kr)) && isfinite(cal.tPeakRx_ms(kr))
    ya = kr - 1 + amp + 0.12;
    plot(ax, [cal.tPeakTx_ms(kr) cal.tPeakRx_ms(kr)], [ya ya], 'k-', 'LineWidth', 0.9);
    plot(ax, cal.tPeakTx_ms(kr), ya, 'k<', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
    plot(ax, cal.tPeakRx_ms(kr), ya, 'k>', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
    text(ax, mean([cal.tPeakTx_ms(kr) cal.tPeakRx_ms(kr)]), ya + 0.07, 'T_{pp}', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
% near field marked on the lowest-frequency trace
x0 = cal.tP_ms(1);  x1 = cal.tS2S_ms(1);
if ~isfinite(x1) || x1 <= x0, x1 = cal.tPeakRx_ms(1); end
if cal.bump(1) > 0.02 && isfinite(x0) && isfinite(x1) && x1 > x0
    rectangle('Parent', ax, 'Position', [x0, -0.32, x1 - x0, 0.64], 'Curvature', [1 1], ...
        'LineStyle', ':', 'EdgeColor', magenta, 'LineWidth', 1.3);
    text(ax, x0, -0.53, 'Near-field effect', 'Color', magenta, 'FontSize', 9, 'FontWeight', 'bold');
end
xlim(ax, [0 xmax]);  ylim(ax, [-0.6, n - 0.35]);
set(ax, 'YTick', []);  box(ax, 'on');
xlabel(ax, 'Time from transmitter start (ms)');
ylabel(ax, 'Transmitted (dashed) and received (solid) signals, each normalised');
vsTxt = '';  if ~isnan(cal.VsFF), vsTxt = sprintf(', V_s = %.1f m/s', cal.VsFF); end
lines3 = {'SIMULATED near-field frequency sweep (Stokes point-force model)', ...
    sprintf('model fitted to T_{pp} = %.1f \\mus at %.3g kHz: far-field T_s = %.1f \\mus%s, V_p/V_s = %.2f, near-field scale %g', ...
    1e6 * cal.refTpp, cal.refF / 1e3, 1e6 * cal.TsFF, vsTxt, cal.ratio, cal.nfScale), ...
    [shapeText(cal.shape) variationText(cal) '   |   ' esc(cal.source)]};
if any(cal.userSet)
    lines3{end+1} = ['* travel time entered by the user at ' ...
        strjoin(arrayfun(@(v) sprintf('%g', v / 1e3), cal.f(cal.userSet).', 'UniformOutput', false), ', ') ' kHz'];
end
title(ax, lines3, 'FontSize', 9);
end

function s = variationText(cal)
s = '';
if cal.variation > 0
    s = sprintf(', random wave variation %g %% (seed %d), receiver band-pass filtered', 100 * cal.variation, cal.seed);
end
end

function fig = plotCalibrationCC(cal, vis)
% normalised cross-correlation of transmitter and (filtered) receiver, one trace per frequency
fig = figure('Name', 'Calibration - cross-correlation (simulated)', 'Color', 'w', 'Visible', vis, ...
    'Units', 'pixels', 'Position', [80 40 900 980]);
ax = axes(fig);  hold(ax, 'on');
n = numel(cal.f);  cols = lines(n);  amp = 0.42;  orange = [0.95 0.55 0.10];
lag = cal.ccLag_ms;  xl = [lag(1) lag(end)];
lagPk = 1e3 * cal.Ts(:, 4);                              % CC travel time, ms
cPk = NaN(n, 1);
for k = 1:n
    off = k - 1;
    plot(ax, xl, [off off], ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);
    plot(ax, lag, off + amp * cal.cc(:, k), '-', 'Color', cols(k, :), 'LineWidth', 1.3);
    if isfinite(lagPk(k)) && lagPk(k) >= lag(1) && lagPk(k) <= lag(end)
        cPk(k) = interp1(lag, cal.cc(:, k), lagPk(k));
        if isnan(cal.VsPP(k)), lab = sprintf('T_{cc} = %.1f \\mus', 1e3 * lagPk(k));
        else,                  lab = sprintf('T_{cc} = %.1f \\mus,  V_s = %.2f (m/s)', 1e3 * lagPk(k), ...
                                   cal.L / (1e-3 * lagPk(k) - cal.Tc));
        end
        text(ax, lagPk(k) + 0.02 * diff(xl), off + amp * cPk(k) + 0.05, lab, 'Color', cols(k, :), 'FontSize', 9);
    end
    text(ax, xl(2) + 0.01 * diff(xl), off, sprintf('%g\n(kHz)', cal.f(k) / 1e3), 'Color', cols(k, :), ...
        'FontWeight', 'bold', 'FontSize', 10, 'Clipping', 'off');
end
ok = isfinite(cPk);
plot(ax, lagPk(ok), find(ok) - 1 + amp * cPk(ok), '-o', 'Color', orange, 'MarkerFaceColor', orange, ...
    'MarkerSize', 4, 'LineWidth', 1.3);
xline(ax, 0, ':k');
xlim(ax, xl);  ylim(ax, [-0.6, n - 0.35]);
set(ax, 'YTick', []);  box(ax, 'on');
xlabel(ax, 'Lag of the receiver relative to the transmitter (ms)');
ylabel(ax, 'Normalised cross-correlation (each trace from -1 to +1)');
title(ax, {'SIMULATED near-field frequency sweep: normalised cross-correlation', ...
    'transmitter with band-pass filtered receiver; marker = maximum = cross-correlation travel time', ...
    esc(cal.source)}, 'FontSize', 9);
end

function fig = plotCalibrationTrend(cal, vis)
% apparent velocity (or travel time) against L/lambda, and near-field strength
fig = figure('Name', 'Calibration - trends (simulated)', 'Color', 'w', 'Visible', vis, ...
    'Units', 'pixels', 'Position', [100 100 1150 480]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);  hold(ax, 'on');
if any(isfinite(cal.VsPP))
    yPP = cal.VsPP;  ySS = cal.VsS2S;  yRef = cal.VsFF;
    ylabel(ax, 'Shear-wave velocity V_s (m/s)');  refLab = sprintf('model V_s = %.1f m/s', yRef);
else
    yPP = 1e6 * cal.Ts(:, 2);  ySS = 1e6 * cal.Ts(:, 1);  yRef = 1e6 * cal.TsFF;
    ylabel(ax, 'Travel time (\mus)');  refLab = sprintf('model far-field T_s = %.1f \\mus', yRef);
end
plot(ax, cal.LL, yPP, '-o', 'Color', [0.10 0.10 0.10], 'MarkerFaceColor', [0.10 0.10 0.10], ...
    'LineWidth', 1.4, 'DisplayName', 'Peak to Peak');
plot(ax, cal.LL, ySS, '--s', 'Color', [0.20 0.45 0.75], 'LineWidth', 1.1, 'DisplayName', 'Start to Start');
if any(cal.userSet)
    plot(ax, cal.LL(cal.userSet), yPP(cal.userSet), 'o', 'MarkerSize', 10, 'Color', [0.85 0.1 0.1], ...
        'LineWidth', 1.3, 'DisplayName', 'T_{pp} entered by the user');
end
if isfinite(yRef)
    yline(ax, yRef, ':', refLab, 'Color', [0.8 0.1 0.1], 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
for k = 1:numel(cal.f)
    if isfinite(cal.LL(k)) && isfinite(yPP(k))
        text(ax, cal.LL(k), yPP(k), sprintf('  %g kHz', cal.f(k) / 1e3), 'FontSize', 8, ...
            'VerticalAlignment', 'top');
    end
end
grid(ax, 'on');  box(ax, 'on');
xlabel(ax, 'L/\lambda (from the peak-to-peak travel time)');
legend(ax, 'Location', 'southeast');
title(ax, 'Apparent velocity against L/\lambda (simulated)');
ax = nexttile(tl);  hold(ax, 'on');
plot(ax, cal.f / 1e3, cal.nfModel, '-o', 'Color', [0.85 0 0.55], 'LineWidth', 1.4, ...
    'MarkerFaceColor', [0.85 0 0.55], 'DisplayName', 'near-field / far-field term (model)');
plot(ax, cal.f / 1e3, cal.bump, '--s', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.1, ...
    'DisplayName', 'first opposite bump / first peak (signal)');
grid(ax, 'on');  box(ax, 'on');
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Relative amplitude');
legend(ax, 'Location', 'northeast');
title(ax, 'Near-field strength (simulated)');
title(tl, {'SIMULATED (Stokes point-force model)', esc(cal.source)}, 'FontSize', 10);
end

function writeCalibrationExcel(cal, file)
% three sheets - Summary, Waveforms, Parameters - enough to redraw the figures
if isfile(file), delete(file); end
n = numel(cal.f);
hdr = [{'f_kHz', 'L_over_lambda', 'L_over_lambda_farfield'}, strcat('Ts_', cal.tags, '_us'), ...
       {'Vs_PP_m_s', 'Vs_S2S_m_s', 'Tpp_model_us', 'Tpp_entered_us', 'user_entered', 'farfield_Ts_us', ...
        'Vp_over_Vs'}, strcat('quality_', cal.tags), ...
       {'near_field_ratio_model', 'first_bump_ratio', 'rx_peak_ms', 'rx_peak_norm', 'tx_peak_ms', ...
        'P_arrival_ms', 'S2S_arrival_ms', 'variation_max_pct', 'variation_rms_pct', 'Tpp_change_by_variation_us'}];
body = [num2cell([cal.f / 1e3, cal.LL, cal.LLff, 1e6 * cal.Ts, cal.VsPP, cal.VsS2S, 1e6 * cal.TppModel, ...
         1e6 * cal.TppEntered, double(cal.userSet), 1e6 * cal.TsFFk, cal.ratioK]), cal.quality, ...
        num2cell([cal.nfModel, cal.bump, cal.tPeakRx_ms, cal.aPeakRxNorm, cal.tPeakTx_ms, cal.tP_ms, cal.tS2S_ms, ...
                  100 * cal.varChange, 100 * cal.varRms, 1e6 * cal.dPPvar])];
writecell(nanToEmpty([hdr; body]), file, 'Sheet', 'Summary');
wh = {'time_ms'};
W = cal.tms;
for k = 1:n
    wh = [wh, {sprintf('tx_%gkHz_V', cal.f(k) / 1e3), sprintf('rx_%gkHz_V', cal.f(k) / 1e3), ...
               sprintf('rx_filtered_%gkHz_V', cal.f(k) / 1e3)}];                                 %#ok<AGROW>
    W = [W, cal.tx(:, k), cal.rx(:, k), cal.rxf(:, k)];                                           %#ok<AGROW>
end
writecell(wh, file, 'Sheet', 'Waveforms', 'Range', 'A1');
writematrix(W, file, 'Sheet', 'Waveforms', 'Range', 'A2');
ch = [{'lag_ms'}, arrayfun(@(v) sprintf('cc_%gkHz', v / 1e3), cal.f(:).', 'UniformOutput', false)];
writecell(ch, file, 'Sheet', 'CrossCorrelation', 'Range', 'A1');
writematrix([cal.ccLag_ms(:), cal.cc], file, 'Sheet', 'CrossCorrelation', 'Range', 'A2');
par = {'item', 'value', 'note';
    'DATA TYPE', 'SIMULATED', 'Stokes point-force near-field model; not measured data';
    'waveform_shape', cal.shape, shapeText(cal.shape);
    'near_field_scale', cal.nfScale, '1 = Stokes solution';
    'random_variation', cal.variation, 'largest random wave change / first-peak height (first peak unchanged)';
    'random_seed', cal.seed, 'seed of the random wave variation';
    'waveform_columns', 3, 'per frequency in Waveforms: tx, rx, rx band-pass filtered';
    'entered_Tpp', sprintf('%d of %d frequencies', nnz(cal.userSet), n), 'see user_entered in Summary';
    'farfield_Ts_us', 1e6 * cal.TsFF, 'model far-field travel time fitted to the reference';
    'Vp_over_Vs', cal.ratio, 'from Poisson''s ratio, or from Vp and L';
    'poisson', cal.poisson, 'used when Vp is not given';
    'Vp_m_s', cal.Vp, 'empty if not given';
    'ref_frequency_kHz', cal.refF / 1e3, 'frequency of the reference peak-to-peak time';
    'ref_Tpp_us', 1e6 * cal.refTpp, 'peak-to-peak travel time the model was fitted to';
    'L_mm', 1e3 * cal.L, 'travel length tip to tip (empty: not given)';
    'Tc_us', 1e6 * cal.Tc, 'time-delay correction applied';
    'Vs_model_m_s', cal.VsFF, 'L / far-field Ts';
    'source', cal.source, 'recorded files the calibration started from';
    'created', cal.created, 'BE_TravelTime_V6'};
writecell(nanToEmpty(par), file, 'Sheet', 'Parameters');
end

function C = nanToEmpty(C)
for k = 1:numel(C)
    if isnumeric(C{k}) && (isempty(C{k}) || (isscalar(C{k}) && isnan(C{k}))), C{k} = ''; end
end
end

function cal = readCalibrationExcel(file)
% rebuild the calibration struct from a workbook written by writeCalibrationExcel
% (V4 workbooks, without the per-frequency columns, are read as all-model)
if ~isfile(file), error('BE:file', 'Calibration workbook not found: %s', file); end
S = readcell(file, 'Sheet', 'Summary');
hdr = cellfun(@(c) char(string(c)), S(1, :), 'UniformOutput', false);
body = S(2:end, :);
n = size(body, 1);
has = @(name) any(strcmp(hdr, name));
col = @(name) body(:, find(strcmp(hdr, name), 1));
num = @(name) cellfun(@cellNum, col(name));
numOpt = @(name) optionalColumn(has(name), num, name, n);
cal.tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
cal.f = 1e3 * num('f_kHz');
cal.LL = num('L_over_lambda');  cal.LLff = num('L_over_lambda_farfield');
cal.Ts = zeros(n, 7);  cal.quality = cell(n, 7);
for j = 1:7
    cal.Ts(:, j) = 1e-6 * num(['Ts_' cal.tags{j} '_us']);
    cal.quality(:, j) = cellfun(@(c) char(string(c)), col(['quality_' cal.tags{j}]), 'UniformOutput', false);
end
cal.VsPP = num('Vs_PP_m_s');  cal.VsS2S = num('Vs_S2S_m_s');
cal.TppModel = 1e-6 * numOpt('Tpp_model_us');
cal.TppEntered = 1e-6 * numOpt('Tpp_entered_us');
cal.userSet = numOpt('user_entered') == 1;
cal.TsFFk = 1e-6 * numOpt('farfield_Ts_us');
cal.ratioK = numOpt('Vp_over_Vs');
cal.nfModel = num('near_field_ratio_model');  cal.bump = num('first_bump_ratio');
cal.tPeakRx_ms = num('rx_peak_ms');  cal.aPeakRxNorm = num('rx_peak_norm');
cal.tPeakTx_ms = num('tx_peak_ms');  cal.tP_ms = num('P_arrival_ms');  cal.tS2S_ms = num('S2S_arrival_ms');
cal.varChange = numOpt('variation_max_pct') / 100;  cal.varRms = numOpt('variation_rms_pct') / 100;
cal.dPPvar = 1e-6 * numOpt('Tpp_change_by_variation_us');
P = readcell(file, 'Sheet', 'Parameters');
key = cellfun(@(c) char(string(c)), P(:, 1), 'UniformOutput', false);
val = @(name) parameterValue(P, key, name);
nPer = cellNum(val('waveform_columns'));                  % 2 in V4/V5 workbooks (tx, rx)
if isnan(nPer), nPer = 2; end
W = readmatrix(file, 'Sheet', 'Waveforms', 'Range', 'A2');
cal.tms = W(:, 1);  cal.tx = W(:, 2:nPer:end);  cal.rx = W(:, 3:nPer:end);
cal.rxf = [];  if nPer >= 3, cal.rxf = W(:, 4:nPer:end); end
cal.ccLag_ms = [];  cal.cc = [];
try                                                      % no such sheet before V6
    Cc = readmatrix(file, 'Sheet', 'CrossCorrelation', 'Range', 'A2');
    cal.ccLag_ms = Cc(:, 1);  cal.cc = Cc(:, 2:end);
catch
end
cal.variation = cellNum(val('random_variation'));  if isnan(cal.variation), cal.variation = 0; end
cal.seed = cellNum(val('random_seed'));
cal.TsFF = 1e-6 * cellNum(val('farfield_Ts_us'));
cal.ratio = cellNum(val('Vp_over_Vs'));
cal.poisson = cellNum(val('poisson'));
cal.Vp = cellNum(val('Vp_m_s'));
cal.refF = 1e3 * cellNum(val('ref_frequency_kHz'));
cal.refTpp = 1e-6 * cellNum(val('ref_Tpp_us'));
cal.L = 1e-3 * cellNum(val('L_mm'));
cal.Tc = 1e-6 * cellNum(val('Tc_us'));
cal.VsFF = cellNum(val('Vs_model_m_s'));
cal.nfScale = cellNum(val('near_field_scale'));
if isnan(cal.nfScale), cal.nfScale = 1; end
cal.shape = char(string(val('waveform_shape')));
if ~ismember(cal.shape, {'recorded', 'ideal'}), cal.shape = 'ideal'; end
cal.source = char(string(val('source')));
cal.created = char(string(val('created')));
end

function v = optionalColumn(present, num, name, n)
if present, v = num(name); else, v = NaN(n, 1); end
end

function v = parameterValue(P, key, name)
k = find(strcmp(key, name), 1);
v = NaN;  if ~isempty(k), v = P{k, 2}; end
end

function v = cellNum(c)
% number from a spreadsheet cell: numeric, numeric text, or empty/missing -> NaN
if isnumeric(c) && isscalar(c), v = double(c);
elseif ischar(c) || isstring(c), v = str2double(c);
else, v = NaN;
end
end

% =========================================================================
%                              DIALOGS
% =========================================================================
function act = askNextStep(pend, nRuns)
fS = 'as recorded';  if ~isempty(pend.f), fS = sprintf('%.3f kHz', pend.f / 1e3); end
tS = 'as measured';  if ~isempty(pend.Ts), tS = sprintf('%s = %.1f us', pend.refMethod, 1e6 * pend.Ts); end
items = {['Change the transmitter frequency   [now: ' fS ']'], ...
         ['Set the travel time   [now: ' tS ']'], ...
         'Calibration: near-field frequency sweep (4-40 kHz, simulated)', ...
         'Reset both to the recorded signals', ...
         'RUN the analysis with these settings', ...
         'Done'};
[sel, ok] = listdlg('ListString', items, 'SelectionMode', 'single', 'InitialValue', 5, ...
    'ListSize', [460 125], 'Name', 'Bender element analysis', ...
    'PromptString', sprintf('%d run(s) so far. What next?', nRuns), ...
    'OKString', 'Select', 'CancelString', 'Done');
acts = {'freq', 'ts', 'cal', 'reset', 'run', 'done'};
act = 'done';
if ok && ~isempty(sel), act = acts{sel}; end
end

function f = askFrequency(f, Rrec, rng, opts)
% returns the new frequency in Hz ([] = recorded); unchanged on Cancel
T0 = Rrec.transmitter;
def = '';  if ~isempty(f), def = sprintf('%.4g', f / 1e3); end
dt = Rrec.dt;
while true
    prompt = sprintf(['Transmitter frequency in kHz (empty = recorded, %.3f kHz).\n' ...
        'This recording supports %.3g-%.3g kHz (coverage >= %.0f %%);\n' ...
        '%.3g-%.3g kHz runs with all results marked [CHECK].'], T0.f.primary / 1e3, ...
        rng.good / 1e3, 100 * opts.simGoodCoverage, rng.min / 1e3);
    a = inputdlg({prompt}, 'Change the transmitter frequency', [1 60], {def});
    if isempty(a), return; end                         % Cancel: keep the previous value
    s = strtrim(a{1});
    if isempty(s), f = []; return; end
    v = str2double(s) * 1e3;
    if ~(isfinite(v) && v > 0 && v < 0.45 / dt)
        uiwait(errordlg(sprintf('Enter a number between 0 and %.4g kHz.', 0.45e-3 / dt), ...
            'Frequency', 'modal'));
        def = s;  continue
    end
    cv = interp1(rng.f, rng.coverage, v, 'linear', 0);
    if cv < opts.simMinCoverage
        uiwait(errordlg(sprintf(['%.4g kHz cannot be predicted from this recording: only %.0f %% ' ...
            'of the pulse energy lies where the recorded pulse has energy. Choose %.3g-%.3g kHz.'], ...
            v / 1e3, 100 * cv, rng.min / 1e3), 'Frequency outside the recorded bandwidth', 'modal'));
        def = s;  continue
    end
    if cv < opts.simGoodCoverage
        b = questdlg(sprintf(['At %.4g kHz only %.0f %% of the pulse energy lies where the ' ...
            'recording is informative. The run will be made, but all its results will be ' ...
            'marked [CHECK].'], v / 1e3, 100 * cv), 'Limited coverage', 'Use it', 'Choose again', 'Choose again');
        if ~strcmp(b, 'Use it'), def = s; continue; end
    end
    f = v;
    return
end
end

function [ts, ref] = askTravelTime(ts, ref, R)
% returns the travel time in s ([] = as measured) and the reference method;
% unchanged on Cancel
M = R.methods(~strcmp({R.methods.tag}, 'MAN'));
items = arrayfun(@(m) sprintf('%-28s %8.1f us', m.name, m.Ts_us), M, 'UniformOutput', false);
k0 = find(strcmp({M.tag}, ref), 1);  if isempty(k0), k0 = 1; end
[sel, ok] = listdlg('ListString', items, 'SelectionMode', 'single', 'InitialValue', k0, ...
    'ListSize', [380 140], 'Name', 'Set the travel time', ...
    'PromptString', {'Which method should return the new travel time?', ...
    '(values of the last run; the receiver is shifted to match)'});
if ~ok || isempty(sel), return; end
def = '';  if ~isempty(ts), def = sprintf('%.2f', 1e6 * ts); end
while true
    a = inputdlg({sprintf('Travel time for %s in us (empty = as measured):', M(sel).name)}, ...
        'Set the travel time', [1 50], {def});
    if isempty(a), return; end
    s = strtrim(a{1});
    if isempty(s), ts = []; ref = M(sel).tag; return; end
    v = str2double(s);
    if ~(isfinite(v) && v > 0)
        uiwait(errordlg('Enter a positive travel time in microseconds.', 'Travel time', 'modal'));
        def = s;  continue
    end
    ts = v * 1e-6;  ref = M(sel).tag;
    return
end
end

% =========================================================================
%                         SOURCES, FOLDERS, SUMMARY
% =========================================================================
function src = sourceInfo(txFile, rxFile, TX, RX, opts) %#ok<INUSD>
src.files = struct('tx', txFile, 'rx', rxFile);
src.meta  = struct('tx', TX.meta, 'rx', RX.meta);
src.txName = TX.name;  src.rxName = RX.name;
src.countsMode = strcmp(TX.mode, 'ADC counts') || strcmp(RX.mode, 'ADC counts');
src.rxLevels = Inf;
if ~isempty(RX.counts), src.rxLevels = RX.levels; end
end

function folder = baseFolder(src, opts)
folder = opts.outputFolder;
if isempty(folder)
    [p, n] = fileparts(src.files.rx);
    folder = fullfile(p, ['BE_results_' n]);
end
end

function folder = runFolder(src, opts, sim)
name = sprintf('run%02d_recorded', sim.runNo);
if sim.isSim
    name = sprintf('run%02d', sim.runNo);
    if ~isempty(sim.fNew), name = sprintf('%s_f%.3fkHz', name, sim.fNew / 1e3); end
    if ~isempty(sim.TsTarget), name = sprintf('%s_%s%.1fus', name, sim.refMethod, 1e6 * sim.TsTarget); end
end
folder = fullfile(baseFolder(src, opts), name);
end

function printRunSummary(Rall, fid)
tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
fprintf(fid, '\n=== Summary of all runs: travel times in us (* = [CHECK]) ===\n');
fprintf(fid, '%-4s %9s %9s %7s', 'Run', 'f_tx kHz', 'f_rx kHz', 'cover.');
fprintf(fid, ' %9s', tags{:});
fprintf(fid, '   Variant\n');
for k = 1:numel(Rall)
    R = Rall{k};
    cv = '-';  if ~isnan(R.sim.coverage), cv = sprintf('%.0f %%', 100 * R.sim.coverage); end
    fprintf(fid, '%-4d %9.3f %9.3f %7s', R.sim.runNo, R.transmitter.f.primary / 1e3, ...
        R.picks.fPeakTrough / 1e3, cv);
    for j = 1:numel(tags)
        m = R.methods(strcmp({R.methods.tag}, tags{j}));
        s = sprintf('%.1f', m.Ts_us);
        if ~strcmp(m.quality, 'ok'), s = [s '*']; end                         %#ok<AGROW>
        fprintf(fid, ' %9s', s);
    end
    fprintf(fid, '   %s\n', R.sim.label);
end
fprintf(fid, '\n');
end

function writeRunSummary(Rall, folder)
if ~exist(folder, 'dir')
    [ok, msg] = mkdir(folder);
    if ~ok, error('BE:save', 'Cannot create the output folder %s: %s', folder, msg); end
end
tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
fid = openOrFail(fullfile(folder, 'all_runs.csv'));
fprintf(fid, 'Run,Variant,f_tx_kHz,f_rx_peak_trough_kHz,coverage');
hdr = [tags; tags];
fprintf(fid, ',%s_us,%s_quality', hdr{:});
fprintf(fid, '\n');
for k = 1:numel(Rall)
    R = Rall{k};
    fprintf(fid, '%d,"%s",%.4f,%.4f,%.3f', R.sim.runNo, R.sim.label, R.transmitter.f.primary / 1e3, ...
        R.picks.fPeakTrough / 1e3, R.sim.coverage);
    for j = 1:numel(tags)
        m = R.methods(strcmp({R.methods.tag}, tags{j}));
        fprintf(fid, ',%.3f,%s', m.Ts_us, m.quality);
    end
    fprintf(fid, '\n');
end
fclose(fid);
fid = openOrFail(fullfile(folder, 'all_runs.txt'));  printRunSummary(Rall, fid);  fclose(fid);
fprintf('Summary of all runs saved in: %s\n', folder);
end

% =========================================================================
%                              OPTIONS
% =========================================================================
function o = defaultOptions(o)
d.countsPerDiv     = 25;
d.rxPolarity       = +1;
d.filterType       = 'fft';
d.filterBand       = [];
d.filterBandFactor = [0.25 4];
d.butterOrder      = 4;
d.minTravelTime    = 0;
d.maxTravelTime    = [];
d.ampFrac          = 0.25;
d.noiseK           = 4;
d.minSNR           = 10;
d.manualPick       = false;
d.L                = [];
d.H_i              = [];
d.dH_c             = 0;
d.H_b              = [];
d.Tc               = 0;
d.rho              = [];
d.saveOutputs      = true;
d.outputFolder     = '';
d.showFigures      = true;
d.interactive      = true;
d.variations       = struct('f', {}, 'Ts', {}, 'refMethod', {});
d.simMinCoverage   = 0.5;
d.simGoodCoverage  = 0.9;
d.calibration      = false;
d.calFrequencies   = [4 8 15 20 30 40] * 1e3;
d.calRefFrequency  = [];
d.calRefTpp        = [];
d.calPoisson       = 0.3;
d.calVp            = [];
d.calShape         = 'recorded';
d.calNearFieldScale = 1;
d.calVariation     = 0.05;
d.calSeed          = 1;
d.calTpp           = [];
d.recreateFromExcel = '';
fn = fieldnames(d);
unknown = setdiff(fieldnames(o), fn);
if ~isempty(unknown)
    warning('BE:opt', 'Unknown option(s) ignored (check the spelling): %s', strjoin(unknown(:).', ', '));
end
for k = 1:numel(fn)
    if ~isfield(o, fn{k}) || (isempty(o.(fn{k})) && ~isempty(d.(fn{k})) && ~ischar(d.(fn{k})))
        o.(fn{k}) = d.(fn{k});
    end
end
o.filterType = lower(o.filterType);
isPos = @(v) isnumeric(v) && isscalar(v) && isfinite(v) && v > 0;
isBand = @(v) isnumeric(v) && numel(v) == 2 && all(isfinite(v)) && v(1) > 0 && v(2) > v(1);
check(ismember(o.rxPolarity, [-1 1]), 'opts.rxPolarity must be +1 or -1.');
check(ismember(o.filterType, {'fft', 'butter', 'none'}), 'opts.filterType must be ''fft'', ''butter'' or ''none''.');
check(isempty(o.filterBand) || isBand(o.filterBand), 'opts.filterBand must be [] or [fLow fHigh] with 0 < fLow < fHigh.');
check(isBand(o.filterBandFactor), 'opts.filterBandFactor must be [a b] with 0 < a < b.');
check(isPos(o.butterOrder) && o.butterOrder == round(o.butterOrder), 'opts.butterOrder must be a positive integer.');
check(isnumeric(o.minTravelTime) && isscalar(o.minTravelTime) && o.minTravelTime >= 0, ...
    'opts.minTravelTime must be a scalar >= 0 (seconds).');
check(isempty(o.maxTravelTime) || (isPos(o.maxTravelTime) && o.maxTravelTime > o.minTravelTime), ...
    'opts.maxTravelTime must be [] or a time (s) larger than opts.minTravelTime.');
check(isPos(o.ampFrac) && o.ampFrac < 1, 'opts.ampFrac must be between 0 and 1.');
check(isPos(o.noiseK), 'opts.noiseK must be positive.');
check(isPos(o.minSNR), 'opts.minSNR must be positive.');
check(isPos(o.simMinCoverage) && isPos(o.simGoodCoverage) && o.simGoodCoverage <= 1 && ...
    o.simMinCoverage <= o.simGoodCoverage, 'Need 0 < opts.simMinCoverage <= opts.simGoodCoverage <= 1.');
% variations: struct array with f (Hz or []), Ts (s or []) and refMethod
if isempty(o.variations), o.variations = d.variations; end
v = o.variations;
check(isstruct(v) && all(isfield(v, {'f', 'Ts'})), ...
    'opts.variations must be a struct array with fields f, Ts (and optionally refMethod).');
if ~isfield(v, 'refMethod'), [v.refMethod] = deal('S2S'); end
tags = {'S2S', 'P2P', 'T2T', 'CC', 'ECC', 'CPS', 'FD'};
for k = 1:numel(v)
    if isempty(v(k).refMethod), v(k).refMethod = 'S2S'; end
    check(isempty(v(k).f) || isPos(v(k).f), sprintf('opts.variations(%d).f must be [] or a frequency in Hz.', k));
    check(isempty(v(k).Ts) || isPos(v(k).Ts), sprintf('opts.variations(%d).Ts must be [] or a time in s.', k));
    check(ischar(v(k).refMethod) && ismember(v(k).refMethod, tags), ...
        sprintf('opts.variations(%d).refMethod must be one of %s.', k, strjoin(tags, ', ')));
end
o.variations = v;
check(isnumeric(o.calFrequencies) && ~isempty(o.calFrequencies) && all(isfinite(o.calFrequencies)) && ...
    all(o.calFrequencies > 0), 'opts.calFrequencies must be a list of positive frequencies (Hz).');
check(isempty(o.calRefFrequency) || isPos(o.calRefFrequency), 'opts.calRefFrequency must be [] or a frequency in Hz.');
check(isempty(o.calRefTpp) || isPos(o.calRefTpp), 'opts.calRefTpp must be [] or a time in s.');
check(isnumeric(o.calPoisson) && isscalar(o.calPoisson) && o.calPoisson >= 0 && o.calPoisson < 0.5, ...
    'opts.calPoisson must be in [0, 0.5).');
check(isempty(o.calVp) || isPos(o.calVp), 'opts.calVp must be [] or a velocity in m/s.');
o.calShape = lower(o.calShape);
check(ismember(o.calShape, {'recorded', 'ideal'}), 'opts.calShape must be ''recorded'' or ''ideal''.');
check(isnumeric(o.calNearFieldScale) && isscalar(o.calNearFieldScale) && o.calNearFieldScale >= 0, ...
    'opts.calNearFieldScale must be >= 0 (1 = Stokes solution).');
check(isnumeric(o.calVariation) && isscalar(o.calVariation) && o.calVariation >= 0 && o.calVariation <= 0.5, ...
    'opts.calVariation must be between 0 and 0.5 (fraction of the first-peak height).');
check(isnumeric(o.calSeed) && isscalar(o.calSeed) && o.calSeed >= 0 && o.calSeed == round(o.calSeed), ...
    'opts.calSeed must be a non-negative integer.');
check(isempty(o.calTpp) || (isnumeric(o.calTpp) && numel(o.calTpp) == numel(o.calFrequencies) && ...
    all(isnan(o.calTpp(:)) | o.calTpp(:) > 0)), ...
    'opts.calTpp must be [] or one travel time (s, NaN = model) per entry of opts.calFrequencies.');
check(ischar(o.recreateFromExcel), 'opts.recreateFromExcel must be a file path (text).');
check(isPos(o.countsPerDiv), 'opts.countsPerDiv must be positive.');
check(isnumeric(o.Tc) && isscalar(o.Tc) && isfinite(o.Tc), 'opts.Tc must be a finite scalar (seconds).');
check(isnumeric(o.dH_c) && isscalar(o.dH_c) && isfinite(o.dH_c), 'opts.dH_c must be a finite scalar (m).');
names = {'L', 'H_i', 'H_b', 'rho'};
for k = 1:numel(names)
    check(isempty(o.(names{k})) || isPos(o.(names{k})), sprintf('opts.%s must be [] or a positive scalar.', names{k}));
end
end

function check(ok, msg)
if ~ok, error('BE:opt', '%s', msg); end
end

% =========================================================================
%                              FILE READING
% =========================================================================
function S = readScopeCSV(file, opts)
txt = fileread(file);
if startsWith(txt, char(65279)), txt = txt(2:end);                 % UTF-8 byte-order mark
elseif startsWith(txt, char([239 187 191])), txt = txt(4:end);
end
[i0, i1] = regexp(txt, '^[ \t]*Waveform Data[^\r\n]*', 'start', 'end', 'once', 'lineanchors', 'ignorecase');
if isempty(i0)
    error('BE:format', 'No "Waveform Data" line found in %s.', file);
end
header = regexp(txt(1:i0-1), '\r\n|\n|\r', 'split');
block  = txt(i1+1:end);
meta = struct();
for k = 1:numel(header)
    parts = strsplit(header{k}, ',');
    key = strtrim(parts{1});
    if isempty(key), continue; end
    val = '';
    if numel(parts) >= 2, val = strtrim(parts{2}); end
    num = str2double(val);
    fld = matlab.lang.makeValidName(key);
    if ~isnan(num), meta.(fld) = num; else, meta.(fld) = val; end
end

% data block: the fast path reads it in one call; irregular files line by line
toSpaces = @(s) regexprep(s, '[,;]', ' ');
probe = regexp(block(1:min(end, 4000)), '\r\n|\n|\r', 'split');
if numel(block) > 4000, probe = probe(1:end-1); end    % last line may be cut
probe = probe(~cellfun(@(s) isempty(strtrim(s)), probe));
nc = cellfun(@(s) numel(sscanf(toSpaces(s), '%f')), probe);
nCol = 0;  if any(nc > 0), nCol = mode(nc(nc > 0)); end
if nCol > 2
    error('BE:format', '%s has %d numeric columns; export one channel per file.', file, nCol);
end
data = [];
if nCol >= 1
    [v, ~, errmsg] = sscanf(toSpaces(block), '%f');
    if isempty(errmsg) && mod(numel(v), nCol) == 0      % every token numeric, whole rows
        data = reshape(v, nCol, []).';
    end
end
if isempty(data)                                       % irregular lines: parse one by one
    body = regexp(block, '\r\n|\n|\r', 'split');
    data = NaN(numel(body), 2);  n = 0;
    for k = 1:numel(body)
        v = sscanf(toSpaces(body{k}), '%f');
        if isempty(v), continue; end
        n = n + 1;
        data(n, 1:min(2, numel(v))) = v(1:min(2, numel(v))).';
    end
    data = data(1:n, :);
    if mean(~isnan(data(:, 2))) > 0.95
        data = data(~isnan(data(:, 2)), :);            % time,value rows only
    else
        data = data(:, 1);
    end
end
n = size(data, 1);
if n < 50, error('BE:format', 'Only %d data points read from %s.', n, file); end

S.file = file;  S.meta = meta;
[~, nm, ex] = fileparts(file);  S.name = [nm ex];
if size(data, 2) == 2                                  % "Detail" export: time, value (V)
    S.mode = 'time,value';
    S.v    = data(:, 2);
    S.counts = [];
    tc = data(:, 1);
    if any(diff(tc) < 0) || ~(tc(end) > tc(1))
        error('BE:format', ['%s: the first of two columns is not a time axis (a two-channel ' ...
            'export?). Export one channel per file.'], S.name);
    end
    % time stamps are often printed with few digits, so steps between rows can
    % repeat or jump: take the step from the header, else from the whole span
    S.dt = (tc(end) - tc(1)) / (n - 1);
    if isfield(meta, 'SamplingPeriod') && isnumeric(meta.SamplingPeriod) && meta.SamplingPeriod > 0
        if abs(meta.SamplingPeriod - S.dt) > 0.01 * S.dt
            warning('BE:timebase', '%s: header Sampling Period %.4g s differs from the time column (%.4g s); the header is used.', ...
                S.name, meta.SamplingPeriod, S.dt);
        end
        S.dt = meta.SamplingPeriod;
    end
    if max(abs(tc - tc(1) - (0:n-1).' * S.dt)) > 0.01 * (tc(end) - tc(1))
        warning('BE:timebase', '%s: time column is not uniform; a constant step of %.4g s is used.', S.name, S.dt);
    end
else                                                   % "Fast" export: ADC counts
    S.mode = 'ADC counts';
    if ~isfield(meta, 'SamplingPeriod') || ~isnumeric(meta.SamplingPeriod) || ~(meta.SamplingPeriod > 0)
        error('BE:format', 'No valid "Sampling Period" in the header of %s.', file);
    end
    S.dt = meta.SamplingPeriod;
    S.counts = data(:, 1);
    vs = 1;
    if isfield(meta, 'VerticalScale') && isnumeric(meta.VerticalScale) && meta.VerticalScale > 0
        vs = meta.VerticalScale;
    else
        warning('BE:noScale', 'No usable "Vertical Scale" in %s; amplitudes left in ADC counts.', S.name);
    end
    S.v = S.counts * vs / opts.countsPerDiv;
    if isfield(meta, 'VerticalPosition') && isnumeric(meta.VerticalPosition) && meta.VerticalPosition ~= 0
        warning('BE:vpos', ['%s: Vertical Position = %g is not applied. The DC offset is ' ...
            'removed anyway, so travel times are unaffected.'], S.name, meta.VerticalPosition);
    end
end
if any(~isfinite(S.v))
    error('BE:format', '%s contains non-numeric samples in the waveform block.', S.name);
end
if isfield(meta, 'MemoryLength') && isnumeric(meta.MemoryLength) && meta.MemoryLength ~= numel(S.v)
    warning('BE:length', '%s: header says %d points, %d read.', S.name, meta.MemoryLength, numel(S.v));
end
S.levels = numel(unique(S.v));
if ~isempty(S.counts) && S.levels < 20
    warning('BE:resolution', ['%s uses only %d distinct ADC levels: the trace is coarsely ' ...
        'quantised. Increase the vertical gain on this channel (D8295 §9.6).'], S.name, S.levels);
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
if isfield(TX.meta, 'Source') && isfield(RX.meta, 'Source') && ischar(TX.meta.Source) && ...
        strcmp(TX.meta.Source, RX.meta.Source)
    warning('BE:source', 'Both files come from channel %s. Check the file selection.', TX.meta.Source);
end
end

% =========================================================================
%                              TRANSMITTER
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

% =========================================================================
%                              RECEIVER
% =========================================================================
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

% =========================================================================
%                     CROSS-CORRELATION / CROSS-SPECTRUM
% =========================================================================
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

% =========================================================================
%                     CROSSTALK FLAGS, VELOCITY AND GMAX
% =========================================================================
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

% =========================================================================
%                              PLOTTING
% =========================================================================
function info = figInfo(src, T, F, opts, sim)
info.ftxLine = sprintf('f_{tx} = %.3f kHz  (full period %.1f \\mus; peak-trough: %.3f kHz)', ...
    T.f.primary/1e3, 1e6*T.period, T.f.peakTrough/1e3);
switch F.type
    case 'none', info.filtLine = 'receiver: unfiltered';
    case 'fft',  info.filtLine = sprintf('receiver: zero-phase FFT band-pass %.2f-%.1f kHz', F.band/1e3);
    otherwise,   info.filtLine = sprintf('receiver: Butterworth (order %d, filtfilt) %.2f-%.1f kHz', ...
                    opts.butterOrder, F.band/1e3);
end
info.files = sprintf('Run %d   |   Tx: %s   |   Rx: %s', sim.runNo, esc(src.txName), esc(src.rxName));
if opts.rxPolarity < 0, info.files = [info.files '   |   Rx inverted']; end
if sim.isSim, info.files = [info.files '   |   SIMULATED: ' esc(sim.label)]; end
info.vis = 'on';  if ~opts.showFigures, info.vis = 'off'; end
info.countsMode = src.countsMode;
info.runNo = sim.runNo;
end

function fig = newFig(name, info)
fig = figure('Name', sprintf('Run %d - %s', info.runNo, name),'Color', 'w', 'Visible', info.vis, 'Units', 'pixels', ...
    'Position', [80 80 1100 760]);
end

function ax = dualAxes(ax, tus, x, tusR, yrRaw, yF)
% transmitter (V) on the left axis, receiver (mV) on the right axis - D8295 Fig. 3 style
yyaxis(ax, 'left');
plot(ax, tus, x, '--', 'Color', [0 0.30 0.70], 'LineWidth', 1.4, 'DisplayName', 'Transmitter');
hold(ax, 'on');
ylabel(ax, 'Transmitter signal (V)');
yl = max(abs(x)) * 1.15;  if ~(yl > 0), yl = 1; end
ylim(ax, [-yl yl]);
yyaxis(ax, 'right');
hold(ax, 'on');
if ~isempty(yrRaw)
    plot(ax, tusR, 1e3*yrRaw, '-', 'Color', [0.85 0.55 0.45], 'LineWidth', 0.5, 'DisplayName', 'Receiver (raw)');
end
plot(ax, tusR, 1e3*yF, '-', 'Color', [0.70 0.10 0.05], 'LineWidth', 1.6, 'DisplayName', 'Receiver (filtered)');
ylabel(ax, 'Receiver signal (mV)');
r = max(abs(1e3*[yF(:); yrRaw(:)])) * 1.15;  if ~(r > 0), r = 1; end
ylim(ax, [-r r]);
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
nfft = fftLength(numel(x), 8);  fa =(0:nfft/2-1).' / nfft / (t(2)-t(1));
Xs = abs(fft(x, nfft));  Yr = abs(fft(yr, nfft));  Yf = abs(fft(y, nfft));
Xs = Xs(1:nfft/2); Yr = Yr(1:nfft/2); Yf = Yf(1:nfft/2);
plot(ax, fa/1e3, Xs/max(eps, max(Xs)), 'Color', [0 0.3 0.7], 'LineWidth', 1.3, 'DisplayName', 'Transmitter'); hold(ax, 'on');
plot(ax, fa/1e3, Yr/max(eps, max(Yf)), 'Color', [0.85 0.55 0.45], 'DisplayName', 'Receiver raw');
plot(ax, fa/1e3, Yf/max(eps, max(Yf)), 'Color', [0.7 0.1 0.05], 'LineWidth', 1.3, 'DisplayName', 'Receiver filtered');
plot(ax, F.fAxis/1e3, F.H, 'k:', 'LineWidth', 1.1, 'DisplayName', 'Filter gain');
xline(ax, T.f.primary/1e3, '--', sprintf('f_{tx} %.2f kHz', T.f.primary/1e3), 'Color', [0 0.3 0.7], 'HandleVisibility', 'off');
if ~isnan(P.fSpec)
    xline(ax, P.fSpec/1e3, '--', sprintf('f_{rx} %.2f kHz', P.fSpec/1e3), 'Color', [0.7 0.1 0.05], ...
        'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
end
grid(ax, 'on');  xlim(ax, [0 min(fa(end), 8*T.f.primary)/1e3]);  ylim(ax, [0 1.3]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Normalised amplitude');
legend(ax, 'Location', 'northeast');  title(ax, 'Amplitude spectra (f_{rx}: spectral peak, unfiltered)');
title(tl, {'Bender element records', info.files}, 'FontWeight', 'bold');
if info.countsMode
    annotation(fig, 'textbox', [0.01 0.0 0.98 0.03], 'String', ...
        sprintf(['Amplitudes scaled as counts x (V/div) / %g; this factor is not verified for your scope ' ...
        'and affects amplitudes only, not times.'], opts.countsPerDiv), ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.4 0.4 0.4], 'Interpreter', 'none');
end
end

function fig = plotS2S(t, x, yr, y, T, P, m, X, info)
fig = newFig('Start to Start', info);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
xr = 1e6 * [-0.3*T.period, max(1.6*T.period, (P.tPeak1 - T.tStart) + 0.6*T.period)];
haveArr = ~isnan(P.tArrival);
for pane = 1:2
    ax = nexttile(tl);
    dualAxes(ax, tus, x, tus, yr, y);
    yyaxis(ax, 'right');
    yline(ax, 0, '-', 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
    if X.detected
        xregion(ax, 1e6*(X.window(1) - T.tStart), 1e6*(X.window(2) - T.tStart), ...
            'FaceColor', [0.6 0.6 0.6], 'FaceAlpha', 0.15, 'DisplayName', 'Crosstalk window');
    end
    if ~isnan(P.tNearField)
        plot(ax, 1e6*(P.tNearField - T.tStart), 1e3*P.aNearField, 'v', 'Color', [0.5 0 0.5], ...
            'MarkerFaceColor', [0.8 0.6 0.9], 'MarkerSize', 8, 'DisplayName', 'Near-field excursion');
    end
    if haveArr
        plot(ax, 1e6*(P.tArrival - T.tStart), 0, 'o', 'Color', [0.7 0.1 0.05], 'MarkerFaceColor', 'y', ...
            'MarkerSize', 9, 'DisplayName', 'Rx arrival (baseline crossing)');
    end
    yyaxis(ax, 'left');
    plot(ax, 0, 0, 's', 'Color', [0 0.3 0.7], 'MarkerFaceColor', 'y', 'MarkerSize', 9, ...
        'DisplayName', 'Tx start');
    xline(ax, 0, ':', 'Color', [0 0.3 0.7], 'HandleVisibility', 'off');
    if haveArr
        xline(ax, 1e6*(P.tArrival - T.tStart), ':', 'Color', [0.7 0.1 0.05], 'HandleVisibility', 'off');
    end
    if pane == 1
        xlim(ax, xr);  legend(ax, 'Location', 'southwest');
        if haveArr
            drawSpan(ax, 0, 1e6*(P.tArrival - T.tStart), sprintf('T_s = %.1f \\mus', 1e6*m.Ts), 0.88);
            title(ax, {sprintf('Start to Start (ASTM D8295 §10.1.2):  T_s = %.1f \\mus', 1e6*m.Ts), info.ftxLine});
        else
            title(ax, {'Start to Start (ASTM D8295 §10.1.2):  not determined', info.ftxLine});
        end
    elseif haveArr
        c = 1e6*(P.tArrival - T.tStart);  w = 1e6*0.35*T.period;
        xlim(ax, [c - w, c + w]);
        title(ax, 'Zoom on the receiver arrival');
    else
        xlim(ax, xr);
        title(ax, 'Zoom on the receiver arrival: no arrival picked');
    end
end
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotPeaks(t, x, yr, y, T, P, mP, mT, info)
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

function fig = plotCC(t, a, b, C, T, m, info, ttl)
fig = newFig(ttl, info);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
tus = 1e6 * (t - T.tStart);
lag = C.lag;  if isnan(lag), lag = 0; end
xr = 1e6 * [-0.3*T.period, max(2*T.period, lag + 1.5*T.period)];
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
if ~isnan(C.lag)
    plot(ax, 1e6*C.lag, C.peak, 'o', 'Color', [0.7 0.1 0.05], 'MarkerFaceColor', 'y', 'MarkerSize', 9, ...
        'DisplayName', sprintf('max at %.1f \\mus (CC = %.3f)', 1e6*C.lag, C.peak));
end
if ~isnan(C.secondLag)
    plot(ax, 1e6*C.secondLag, C.secondPeak, 'd', 'Color', [0.4 0.4 0.4], 'MarkerSize', 8, ...
        'DisplayName', sprintf('runner-up at %.1f \\mus (%.0f %%)', 1e6*C.secondLag, 100*C.secondPeak/C.peak));
end
xline(ax, 0, ':k', 'HandleVisibility', 'off');
grid(ax, 'on');  xlim(ax, [-xr(2) xr(2)]);  ylim(ax, [-1 1]);
xlabel(ax, 'Lag of receiver relative to transmitter (\mus)');  ylabel(ax, 'Normalised CC');
legend(ax, 'Location', 'southwest');
if isnan(m.Ts), title(ax, sprintf('%s:  not determined', ttl));
else,           title(ax, sprintf('%s:  T_s = %.1f \\mus', ttl, 1e6*m.Ts));
end
% (3) alignment check: transmitter shifted by the CC lag over the receiver
ax = nexttile(tl);
plot(ax, tus + 1e6*lag, a / max(eps, max(abs(a))), '--', 'Color', [0 0.3 0.7], 'LineWidth', 1.4, ...
    'DisplayName', sprintf('Transmitter shifted by %.1f \\mus', 1e6*lag)); hold(ax, 'on');
plot(ax, tus, b / max(eps, max(abs(b))), '-', 'Color', [0.7 0.1 0.05], 'LineWidth', 1.6, 'DisplayName', 'Receiver');
grid(ax, 'on');  xlim(ax, xr);  ylim(ax, [-1.15 1.15]);
xlabel(ax, 'Time from transmitter start (\mus)');  ylabel(ax, 'Normalised amplitude');
legend(ax, 'Location', 'southwest');  title(ax, 'Alignment check (each trace scaled to its own maximum)');
title(tl, info.files, 'FontWeight', 'normal', 'FontSize', 9);
end

function fig = plotCPS(S, m, f0, info)
fig = newFig('Cross-power spectrum', info);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
haveFit = ~any(isnan(S.band));
if haveFit, fmax = min(S.f(end), 4 * mean(S.band)); else, fmax = min(S.f(end), 4 * f0); end
ax = nexttile(tl);
plot(ax, S.f/1e3, S.X/max(eps, max(S.X)), '--', 'Color', [0 0.3 0.7], 'LineWidth', 1.4, 'DisplayName', '|Transmitter|'); hold(ax, 'on');
plot(ax, S.f/1e3, S.Y/max(eps, max(S.Y)), '-', 'Color', [0.7 0.1 0.05], 'LineWidth', 1.4, 'DisplayName', '|Receiver (filtered)|');
plot(ax, S.f/1e3, S.Gmag/max(eps, max(S.Gmag)), 'k:', 'LineWidth', 1.2, 'DisplayName', '|Cross-power spectrum|');
if haveFit
    xregion(ax, S.band(1)/1e3, S.band(2)/1e3, 'FaceColor', [0.9 0.8 0.3], 'FaceAlpha', 0.25, 'DisplayName', 'Fit band');
end
grid(ax, 'on');  xlim(ax, [0 fmax/1e3]);  ylim(ax, [0 1.15]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Normalised magnitude');  legend(ax, 'Location', 'northeast');
title(ax, {'Amplitude spectra of both signals', info.ftxLine});
ax = nexttile(tl);
k = S.f <= fmax;
plot(ax, S.f(k)/1e3, S.phase(k), '-', 'Color', [0.6 0.6 0.6], 'DisplayName', 'Unwrapped phase'); hold(ax, 'on');
if haveFit
    plot(ax, S.fFit/1e3, S.phFit, 'k.', 'MarkerSize', 8, 'DisplayName', 'Fitted points');
    plot(ax, S.fFit/1e3, S.phModel, 'r-', 'LineWidth', 1.8, ...
        'DisplayName', sprintf('slope \\rightarrow \\tau = %.1f \\mus (R^2 = %.3f)', 1e6*S.tau, S.R2));
end
grid(ax, 'on');  xlim(ax, [0 fmax/1e3]);
xlabel(ax, 'Frequency (kHz)');  ylabel(ax, 'Phase of cross-power spectrum (rad)');  legend(ax, 'Location', 'southwest');
if haveFit
    title(ax, sprintf('Cross-power spectrum phase slope (group delay):  T_s = %.1f \\mus', 1e6*m.Ts));
else
    title(ax, 'Cross-power spectrum phase slope: no usable fit band');
end
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
xlo = min(0, min(good));  xhi = 1.6 * max(good);
if ~(xhi > xlo), xhi = xlo + 1; end
xlim(ax, [xlo, xhi]);
grid(ax, 'on');  xlabel(ax, 'Shear-wave travel time T_s (\mus)');
title(ax, {'Travel time by method', info.ftxLine, ...
    'green: ASTM D8295   blue: other methods (§10.2, need validation)   grey: informational', ...
    sprintf('unfiltered-receiver CC check: %.1f \\mus   |   T_c = %.1f \\mus', 1e6*Craw.lag, 1e6*opts.Tc)});
end

function drawSpan(ax, x1, x2, label, yFrac)
if ~(isfinite(x1) && isfinite(x2)), return; end
yl = ylim(ax);  yv = yl(1) + yFrac * diff(yl);
plot(ax, [x1 x2], [yv yv], 'k-', 'LineWidth', 1.1, 'HandleVisibility', 'off');
plot(ax, [x1 x2], [yv yv], 'k|', 'MarkerSize', 12, 'LineWidth', 1.1, 'HandleVisibility', 'off');
text(ax, (x1 + x2)/2, yv, label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontWeight', 'bold', 'BackgroundColor', 'w', 'Margin', 1);
end

function [ts, ok] = manualPick(t, x, y, T, info)
info.vis = 'on';                                   % the pick needs a visible figure
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
T = R.transmitter;  F = R.filter;  P = R.picks;  M = R.methods;  o = R.options;  X = R.crosstalk;
[~, a, b] = fileparts(R.files.tx);  [~, c, d] = fileparts(R.files.rx);
fprintf(fid, '\n=== Bender element travel-time analysis (ASTM D8295-19) ===\n');
fprintf(fid, 'Transmitter file : %s\nReceiver file    : %s\n', [a b], [c d]);
fprintf(fid, 'Sampling period  : %.3g us  (%.3g MHz), %d points, record %.1f us\n', ...
    1e6*R.dt, 1e-6/R.dt, numel(T.x), 1e6*R.dt*numel(T.x));
sim = R.sim;
if ~sim.isSim
    fprintf(fid, 'Run %d          : recorded signals\n', sim.runNo);
else
    fprintf(fid, 'Run %d          : SIMULATED VARIANT of the recorded pair - %s\n', sim.runNo, sim.label);
    if ~isempty(sim.fNew)
        fprintf(fid, ['  transmitter replaced by a single-cycle sine at %.3f kHz; receiver predicted with ' ...
            'the transfer function\n  measured from the recording (linear, time-invariant system). ' ...
            'Coverage %.0f %% (reliable >= %.0f %%).\n'], sim.fNew/1e3, 100*sim.coverage, ...
            100*o.simGoodCoverage);
    end
    if ~isempty(sim.TsTarget)
        fprintf(fid, ['  receiver shifted %+.2f us: %s %.2f us before the shift, requested %.2f us, ' ...
            'obtained %.2f us.\n  Waveform unchanged by the shift (attenuation, dispersion and ' ...
            'near-field size not modelled).\n'], 1e6*sim.shift, sim.refMethod, 1e6*sim.TsRef, ...
            1e6*sim.TsTarget, 1e6*sim.TsObtained);
    end
end
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
fprintf(fid, '  noise (pre-trigger, robust std): raw %.3g mV, filtered %.3g mV; peak SNR %.0f (minimum %g)\n', ...
    1e3*F.noiseRaw, 1e3*F.noiseFilt, P.snr, o.minSNR);
fprintf(fid, '  frequency, peak-to-trough x 2   : %.3f kHz  (rx / tx = %.2f)\n', ...
    P.fPeakTrough/1e3, P.fPeakTrough/T.f.peakTrough);
fprintf(fid, '  frequency, spectral peak        : %.3f kHz  (rx / tx = %.2f)\n', ...
    P.fSpec/1e3, P.fSpec/T.f.spectralPeak);
fprintf(fid, '  (D8295 §9.8 expects the received frequency to be about the transmitted one)\n');
if ~isnan(P.tNearField)
    fprintf(fid, '  near-field excursion at %.1f us after tx start (%.3g mV)\n', ...
        1e6*(P.tNearField - T.tStart), 1e3*P.aNearField);
end
if ~isnan(P.tFilterDip)
    fprintf(fid, ['  dip at %.1f us after tx start is in the filtered trace only (filter ringing), ' ...
        'not reported as near field\n'], 1e6*(P.tFilterDip - T.tStart));
end
if X.detected
    fprintf(fid, ['  CROSSTALK: %.3g mV while the transmitter is active (correlation %.2f); ' ...
        'picks earlier than %.1f us are marked [CHECK]\n'], 1e3*X.amp, X.corr, 1e6*X.minTravelTimeHint);
end
if o.minTravelTime > 0
    fprintf(fid, '  picks restricted to travel times >= %.1f us (opts.minTravelTime)\n', 1e6*o.minTravelTime);
end
fprintf(fid, '\n  %-28s %-34s %9s %8s %8s %9s  %s\n', 'Method', 'Basis', 'Ts (us)', 'f*Ts', ...
    'Vs(m/s)', 'Gmax(MPa)', 'Note');
for k = 1:numel(M)
    fprintf(fid, '  %-28s %-34s %9.1f %8.2f %8.0f %9.1f  %s%s\n', M(k).name, M(k).basis, M(k).Ts_us, ...
        M(k).wavelengthsInPath_tx, M(k).Vs, M(k).Gmax_MPa, M(k).note, ...
        ternary(strcmp(M(k).quality, 'ok'), '', '  [CHECK]'));
end
fprintf(fid, '  Filter-sensitivity check, CC on the UNFILTERED receiver: %.1f us\n', 1e6*R.ccRaw.lag);
fprintf(fid, '  f*Ts = travel path length in transmitted wavelengths (L/lambda); Tc = %.2f us applied.\n', 1e6*o.Tc);
if o.Tc == 0
    fprintf(fid, '  NOTE: Tc = 0. D8295 §8.1 asks for a tip-to-tip calibration of the system delay.\n');
end
s2s = M(1).Ts;  p2p = M(2).Ts;
if ~isnan(s2s) && ~isnan(p2p)
    fprintf(fid, '  Start-to-Start vs Peak-to-Peak differ by %.1f us (%.0f %% of their mean).\n', ...
        1e6*abs(s2s - p2p), 200*abs(s2s - p2p)/abs(s2s + p2p));
end
fprintf(fid, '\n');
end

function folder = saveOutputs(R, figs, folder)
if ~exist(folder, 'dir')
    [ok, msg] = mkdir(folder);
    if ~ok, error('BE:save', 'Cannot create the output folder %s: %s', folder, msg); end
end
for k = 1:numel(figs)
    if ~isgraphics(figs(k)), continue; end
    nm = regexprep(get(figs(k), 'Name'), '[^\w]+', '_');
    try
        exportgraphics(figs(k), fullfile(folder, sprintf('%02d_%s.png', k, nm)), 'Resolution', 200);
    catch err
        warning('BE:save', 'Figure "%s" not saved: %s', get(figs(k), 'Name'), err.message);
    end
end
% methods table (plain CSV, readable anywhere)
fid = openOrFail(fullfile(folder, 'travel_times.csv'));
fprintf(fid, 'Method,Basis,Ts_s,Ts_us,f_tx_times_Ts,Vs_m_s,Gmax_MPa,Quality,Note\n');
M = R.methods;
for k = 1:numel(M)
    fprintf(fid, '"%s","%s",%.9g,%.3f,%.4f,%.4g,%.4g,%s,"%s"\n', M(k).name, M(k).basis, M(k).Ts, ...
        M(k).Ts_us, M(k).wavelengthsInPath_tx, M(k).Vs, M(k).Gmax_MPa, M(k).quality, strrep(M(k).note, '"', ''''));
end
fclose(fid);
fid = openOrFail(fullfile(folder, 'report.txt'));  printReport(R, fid);  fclose(fid);
Rsave = rmfield(R, 'figures');  %#ok<NASGU>
save(fullfile(folder, 'BE_results.mat'), 'Rsave');
fprintf('Results saved in: %s\n', folder);
end

function fid = openOrFail(file)
fid = fopen(file, 'w');
if fid < 0, error('BE:save', 'Cannot write %s (file open in another program?).', file); end
end

% =========================================================================
%                              HELPERS
% =========================================================================
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

function s = esc(s)
s = strrep(s, '_', '\_');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
