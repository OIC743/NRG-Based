%% =========================================================================
%  BENDER-ELEMENT FREQUENCY SWEEPS: NT AGAINST M-TREATED  (plotting script)
%  BE_CompareSweeps  |  reads two calibration workbooks (BE_TravelTime_V6)
%  =========================================================================
%
%  HOW TO RUN: edit the USER SETTINGS block and run the script (F5). Leave
%  ntFile / mFile empty to be asked for each workbook in turn.
%
%  INPUT: two workbooks written by the calibration of BE_TravelTime_V5/V6
%  ("calibration_nearfield.xlsx": sheets Summary, Waveforms, Parameters).
%
%  ONE FIGURE, FOUR PANELS
%   (a) NT sweep: transmitted (dashed) and received (solid, band-pass
%       filtered) signals at every frequency, as Figure 8 of
%       BE_TravelTime_V6: Vs and L/lambda per trace, frequency labels,
%       first-peak picks joined in orange, T_pp arrow on the test (sending)
%       frequency, near field marked on the lowest frequency
%   (b) M-treated sweep, same layout
%   (c) Vs relative to the test frequency (%) against the excitation
%       frequency f (log axis), +-2 % band, test frequencies dotted
%   (d) the same against R_d = L f / Vs (wavelengths between the tips),
%       R_d = 2 line, stars at the test frequencies
%
%  Vs relative to the test frequency = 100 * (Vs(f) / Vs(f_test) - 1), with
%  Vs = L / (Ts - Tc) from the chosen method (default peak to peak) and
%  R_d = f * (Ts - Tc) = L f / Vs. The test frequency is the workbook's
%  reference frequency unless set below; if it is not one of the sweep
%  frequencies, Vs there is interpolated (pchip in log f). Results whose
%  quality is not 'ok' are drawn as open grey circles and left out of the
%  lines.
%
%  The workbooks' provenance (SIMULATED, near-field scale, travel times
%  entered by the user) is printed in a footnote of the figure.
%  If a workbook has no Parameters sheet, L and Tc are recovered from its
%  Summary sheet (L/lambda = f (T_pp - Tc), Vs = L / (T_pp - Tc)), the test
%  frequency must be set below, and the footnote says that the sheet - and
%  with it the recorded data type - is missing.
%
%  OUTPUT: the figure, cfg.widthMM wide (default 190 mm), plus, when
%  saveOutputs is true, <outputFile>.eps (vector, for Adobe Illustrator),
%  .pdf (vector), .png (600 dpi) - all exactly widthMM x heightMM - and
%  .csv (the plotted numbers). Nothing is transparent, so the EPS stays
%  fully vector.
%  Font: Charis SIL (free, SIL International); if it is not installed,
%  MATLAB substitutes another font and a warning says so. The EPS refers to
%  the font by name: Illustrator needs Charis SIL installed to show and
%  edit the text in it.
%  Requires MATLAB R2022a or later (print -vector).
%  =========================================================================

%% ============================ USER SETTINGS ==============================
ntFile = '';                            % NT workbook ('' -> file dialog)
mFile  = '';                            % M-treated workbook ('' -> file dialog)

cfg = struct();
cfg.ntLabel         = 'NT';             % legend / title names
cfg.mLabel          = 'M-treated';
cfg.ntTestFrequency = [];               % kHz; [] -> reference frequency stored in the workbook
cfg.mTestFrequency  = [];               % kHz; [] -> reference frequency stored in the workbook
cfg.method          = 'P2P';            % travel time behind Vs: 'P2P' | 'S2S' | 'T2T' | 'CC' | 'ECC' | 'CPS'
cfg.band            = 2;                % % half-width of the grey band in (c) and (d)
cfg.rdLine          = 2;                % R_d of the dashed line in (d) ([] = none)
cfg.fontName        = 'Charis SIL';
cfg.fontSize        = 8;                % pt, axis labels and titles (trace labels 1 pt smaller)
cfg.widthMM         = 190;              % figure width, mm
cfg.heightMM        = 200;              % figure height, mm
cfg.saveOutputs     = true;
cfg.outputFile      = '';               % '' -> BE_CompareSweeps next to the M-treated workbook
%% =========================================================================

cfg = checkSettings(cfg);
figsBefore = findall(groot, 'Type', 'figure');           % to remove any empty figure left behind
if isempty(ntFile)
    [f, p] = uigetfile({'*.xlsx', 'Calibration workbook (*.xlsx)'}, ['Select the ' cfg.ntLabel ' workbook']);
    if isequal(f, 0), disp('No workbook selected - cancelled.'); return; end
    ntFile = fullfile(p, f);
end
if isempty(mFile)
    [f, p] = uigetfile({'*.xlsx', 'Calibration workbook (*.xlsx)'}, ['Select the ' cfg.mLabel ' workbook'], ...
        [fileparts(ntFile) filesep]);
    if isequal(f, 0), disp('No workbook selected - cancelled.'); return; end
    mFile = fullfile(p, f);
end

% ---- data -----------------------------------------------------------------
A = readSweep(ntFile, cfg.ntTestFrequency, cfg);  A.label = cfg.ntLabel;
B = readSweep(mFile,  cfg.mTestFrequency,  cfg);  B.label = cfg.mLabel;
A.color = [0.55 0.42 0.13];  A.marker = 's';          % NT: brown squares
B.color = [0.00 0.45 0.74];  B.marker = 'o';          % M-treated: blue circles

% ---- figure ---------------------------------------------------------------
fontOk = any(strcmpi(listfonts, cfg.fontName));
if ~fontOk
    warning('BEC:font', ['Font "%s" is not installed; MATLAB uses another font. Install it ' ...
        '(free from SIL International) and restart MATLAB.'], cfg.fontName);
end
fig = figure('Name', 'NT vs M-treated frequency sweeps', 'Color', 'w', 'Units', 'centimeters', ...
    'Position', [2 2 cfg.widthMM / 10 cfg.heightMM / 10]);
set(fig, 'PaperUnits', 'centimeters', 'PaperSize', [cfg.widthMM cfg.heightMM] / 10, ...
    'PaperPosition', [0 0 cfg.widthMM cfg.heightMM] / 10, 'InvertHardcopy', 'off');
set(fig, 'DefaultAxesFontName', cfg.fontName, 'DefaultTextFontName', cfg.fontName, ...
    'DefaultAxesFontSize', cfg.fontSize, 'DefaultTextFontSize', cfg.fontSize);
tl = tiledlayout(fig, 5, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
plotSweep(nexttile(tl, 1, [3 1]), A, '(a)', cfg);
plotSweep(nexttile(tl, 2, [3 1]), B, '(b)', cfg);
axC = nexttile(tl, 7, [2 1]);
hLeg = plotRelative(axC, {A, B}, 'f', cfg);
plotRelative(nexttile(tl, 8, [2 1]), {A, B}, 'Rd', cfg);
lg = legend(axC, hLeg.handles, hLeg.labels, 'Orientation', 'horizontal', 'Box', 'off');
lg.Layout.Tile = 'north';
annotation(fig, 'textbox', [0.01 0.002 0.98 0.02], 'String', provenance({A, B}), ...
    'EdgeColor', 'none', 'FontSize', max(5, cfg.fontSize - 2), 'Color', [0.35 0.35 0.35], ...
    'Interpreter', 'none', 'HorizontalAlignment', 'left');
set(findall(fig, '-property', 'FontName'), 'FontName', cfg.fontName);
closeEmptyFigures(figsBefore, fig);

% ---- report and files -----------------------------------------------------
printComparison({A, B}, cfg, 1);
if cfg.saveOutputs
    out = cfg.outputFile;
    if isempty(out), out = fullfile(fileparts(mFile), 'BE_CompareSweeps'); end
    % print uses the paper size set above, so every file is exactly widthMM x heightMM
    print(fig, [out '.eps'], '-depsc', '-vector');
    print(fig, [out '.pdf'], '-dpdf', '-vector');
    print(fig, [out '.png'], '-dpng', '-r600');
    writeComparisonCsv({A, B}, cfg, [out '.csv']);
    fprintf('Saved (%g x %g mm): %s.eps, .pdf, .png, .csv\n', cfg.widthMM, cfg.heightMM, out);
    closeEmptyFigures(figsBefore, fig);
end

% =========================================================================
%                              SETTINGS AND DATA
% =========================================================================
function closeEmptyFigures(figsBefore, keep)
% close figures that appeared while the script ran but hold nothing
for h = reshape(findall(groot, 'Type', 'figure'), 1, [])
    if isequal(h, keep) || any(figsBefore == h), continue; end
    if isempty(h.Children), close(h); end
end
end

function cfg = checkSettings(cfg)
tags = {'P2P', 'S2S', 'T2T', 'CC', 'ECC', 'CPS'};
cfg.method = upper(cfg.method);
if ~ismember(cfg.method, tags)
    error('BEC:opt', 'cfg.method must be one of %s.', strjoin(tags, ', '));
end
for nm = {'ntTestFrequency', 'mTestFrequency'}
    v = cfg.(nm{1});
    if ~(isempty(v) || (isnumeric(v) && isscalar(v) && v > 0))
        error('BEC:opt', 'cfg.%s must be [] or a frequency in kHz.', nm{1});
    end
end
if ~(isnumeric(cfg.band) && isscalar(cfg.band) && cfg.band >= 0)
    error('BEC:opt', 'cfg.band must be a non-negative percentage.');
end
for nm = {'widthMM', 'heightMM', 'fontSize'}
    v = cfg.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && v > 0)
        error('BEC:opt', 'cfg.%s must be a positive number.', nm{1});
    end
end
end

function D = readSweep(file, testF_kHz, cfg)
% one calibration workbook -> struct with signals, travel times, Vs and R_d
if ~isfile(file), error('BEC:file', 'Workbook not found: %s', file); end
[~, nm, ex] = fileparts(file);  D.file = file;  D.name = [nm ex];
S = readcell(file, 'Sheet', 'Summary');
hdr = cellfun(@cellText, S(1, :), 'UniformOutput', false);
body = S(2:end, :);  n = size(body, 1);
has = @(name) any(strcmp(hdr, name));
col = @(name) body(:, find(strcmp(hdr, name), 1));
num = @(name) cellfun(@cellNum, col(name));
need = {'f_kHz', ['Ts_' cfg.method '_us'], ['quality_' cfg.method], 'rx_peak_ms', 'rx_peak_norm', 'tx_peak_ms'};
for k = 1:numel(need)
    if ~has(need{k}), error('BEC:format', '%s: column "%s" missing in sheet Summary.', D.name, need{k}); end
end
D.f = 1e3 * num('f_kHz');
D.Ts = 1e-6 * num(['Ts_' cfg.method '_us']);
D.TsPP = 1e-6 * num('Ts_P2P_us');
D.ok = strcmp(cellfun(@cellText, col(['quality_' cfg.method]), 'UniformOutput', false), 'ok');
D.userSet = false(n, 1);  if has('user_entered'), D.userSet = num('user_entered') == 1; end
D.tPeakRx_ms = num('rx_peak_ms');  D.aPeakRxNorm = num('rx_peak_norm');  D.tPeakTx_ms = num('tx_peak_ms');
D.tP_ms = NaN(n, 1);    if has('P_arrival_ms'), D.tP_ms = num('P_arrival_ms'); end
D.tS2S_ms = NaN(n, 1);  if has('S2S_arrival_ms'), D.tS2S_ms = num('S2S_arrival_ms'); end
D.bump = zeros(n, 1);   if has('first_bump_ratio'), D.bump = num('first_bump_ratio'); end
% parameters (sheet may be missing, e.g. after editing the workbook)
D.hasParameters = true;
try
    P = readcell(file, 'Sheet', 'Parameters');
catch
    P = cell(0, 2);  D.hasParameters = false;
    warning('BEC:format', '%s has no Parameters sheet: L and Tc are taken from the Summary sheet.', D.name);
end
key = cellfun(@cellText, P(:, 1), 'UniformOutput', false);
val = @(name) parameterValue(P, key, name);
D.L = 1e-3 * cellNum(val('L_mm'));
D.Tc = 1e-6 * cellNum(val('Tc_us'));
D.refF = 1e3 * cellNum(val('ref_frequency_kHz'));
D.dataType = cellText(val('DATA TYPE'));
D.nfScale = cellNum(val('near_field_scale'));
D.variation = cellNum(val('random_variation'));
if isnan(D.Tc) && has('L_over_lambda')                   % L/lambda = f (T_pp - Tc)
    D.Tc = medianFinite(D.TsPP - num('L_over_lambda') ./ D.f);
end
if isnan(D.Tc), D.Tc = 0; end
if isnan(D.L) && has('Vs_PP_m_s')                        % Vs_PP = L / (T_pp - Tc)
    D.L = medianFinite(num('Vs_PP_m_s') .* (D.TsPP - D.Tc));
end
% waveforms (tx, rx[, rx filtered] per frequency)
W = readmatrix(file, 'Sheet', 'Waveforms', 'Range', 'A2');
nPer = cellNum(val('waveform_columns'));
if isnan(nPer), nPer = (size(W, 2) - 1) / n; end           % 2: tx, rx   3: tx, rx, rx filtered
if ~ismember(nPer, [2 3])
    error('BEC:format', '%s: Waveforms has %d columns for %d frequencies.', D.name, size(W, 2), n);
end
D.tms = W(:, 1);  D.tx = W(:, 2:nPer:end);  D.rx = W(:, 3:nPer:end);
D.rxShow = D.rx;  if nPer >= 3, D.rxShow = W(:, 4:nPer:end); end
if size(D.tx, 2) ~= n
    error('BEC:format', '%s: %d frequencies in Summary but %d in Waveforms.', D.name, n, size(D.tx, 2));
end
% velocity, R_d and the test frequency
if ~isnan(D.L)
    D.Vs = D.L ./ (D.Ts - D.Tc);
elseif strcmp(cfg.method, 'P2P') && has('Vs_PP_m_s')
    D.Vs = num('Vs_PP_m_s');
else
    error('BEC:format', '%s: no travel length L in Parameters, so Vs cannot be computed.', D.name);
end
D.Rd = D.f .* (D.Ts - D.Tc);                             % = L f / Vs
D.fTest = D.refF;  if ~isempty(testF_kHz), D.fTest = 1e3 * testF_kHz; end
if isnan(D.fTest)
    error('BEC:format', '%s: no test frequency stored in the workbook; set cfg.ntTestFrequency / cfg.mTestFrequency (kHz).', D.name);
end
[D.VsTest, D.RdTest, D.testInSweep] = atTestFrequency(D);
D.rel = 100 * (D.Vs / D.VsTest - 1);
end

function [VsT, RdT, inSweep] = atTestFrequency(D)
% Vs and R_d at the test frequency: the sweep value, or pchip in log f
k = find(abs(D.f - D.fTest) <= 1e-6 * D.fTest & D.ok, 1);
inSweep = ~isempty(k);
if inSweep, VsT = D.Vs(k);  RdT = D.Rd(k);  return; end
g = D.ok & isfinite(D.Vs);
if nnz(g) < 2 || D.fTest < min(D.f(g)) || D.fTest > max(D.f(g))
    error('BEC:test', '%s: test frequency %g kHz is outside the usable sweep (%g-%g kHz).', ...
        D.name, D.fTest / 1e3, min(D.f(g)) / 1e3, max(D.f(g)) / 1e3);
end
VsT = interp1(log(D.f(g)), D.Vs(g), log(D.fTest), 'pchip');
RdT = interp1(log(D.f(g)), D.Rd(g), log(D.fTest), 'pchip');
warning('BEC:test', '%s: test frequency %g kHz is not in the sweep; Vs there is interpolated.', ...
    D.name, D.fTest / 1e3);
end

function m = medianFinite(v)
v = v(isfinite(v));
m = NaN;  if ~isempty(v), m = median(v); end
end

function v = parameterValue(P, key, name)
k = find(strcmp(key, name), 1);
v = NaN;  if ~isempty(k), v = P{k, 2}; end
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
%                                 PANELS
% =========================================================================
function plotSweep(ax, D, letter, cfg)
% stacked transmitted / received signals, one trace per frequency (Figure 8 style)
hold(ax, 'on');
n = numel(D.f);  cols = lines(n);  amp = 0.42;
orange = [0.95 0.55 0.10];  magenta = [0.85 0 0.55];
xmax = min(D.tms(end), max(D.tPeakRx_ms + 1.1e3 ./ D.f));        % end of the slowest received pulse
[~, kT] = min(abs(D.f - D.fTest));                                % trace of the test (sending) frequency
yPk = NaN(n, 1);
for k = 1:n
    off = k - 1;
    sx = amp / max(eps, max(abs(D.tx(:, k))));
    sy = amp / max(eps, max(abs(D.rxShow(:, k))));
    plot(ax, [0 xmax], [off off], ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);
    plot(ax, D.tms, off + sx * D.tx(:, k), '--', 'Color', [0.30 0.30 0.30], 'LineWidth', 0.9);
    plot(ax, D.tms, off + sy * D.rxShow(:, k), '-', 'Color', cols(k, :), 'LineWidth', 1.3);
    yPk(k) = off + amp * D.aPeakRxNorm(k) * max(abs(D.rx(:, k))) / max(eps, max(abs(D.rxShow(:, k))));
    lab = sprintf('V_s = %.2f (m/s)', D.Vs(k));
    if D.userSet(k), lab = [lab ' *']; end                                         %#ok<AGROW>
    if ~D.ok(k), lab = [lab ' (check)']; end                                       %#ok<AGROW>
    if isfinite(D.tPeakRx_ms(k)) && isfinite(yPk(k))
        text(ax, D.tPeakRx_ms(k) + 0.02 * xmax, yPk(k) + 0.06, lab, 'Color', cols(k, :), 'FontSize', cfg.fontSize - 1);
    end
    % frequency above and L/lambda below the trace, inside the panel at its right edge
    % (labels outside the axes would run into the neighbouring panel at 190 mm width)
    fLab = sprintf('%g kHz', D.f(k) / 1e3);
    if k == kT, fLab = [fLab ' (test)']; end                                       %#ok<AGROW>
    text(ax, 0.99 * xmax, off + 0.17, fLab, 'Color', cols(k, :), 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right', 'FontSize', cfg.fontSize, 'BackgroundColor', 'w', 'Margin', 0.5);
    text(ax, 0.99 * xmax, off - 0.22, sprintf('L/\\lambda = %.2f', D.f(k) * (D.TsPP(k) - D.Tc)), ...
        'HorizontalAlignment', 'right', 'FontSize', cfg.fontSize - 1, 'BackgroundColor', 'w', 'Margin', 0.5);
end
if strcmp(cfg.method, 'P2P')                             % first-peak picks joined across frequencies
    ok = isfinite(D.tPeakRx_ms) & isfinite(yPk);
    plot(ax, D.tPeakRx_ms(ok), yPk(ok), '-o', 'Color', orange, 'MarkerFaceColor', orange, ...
        'MarkerSize', 4, 'LineWidth', 1.3);
else                                                     % travel time of the method as a tick per trace
    tt = 1e3 * D.Ts;  ok = isfinite(tt);
    for k = find(ok).'
        plot(ax, [tt(k) tt(k)], k - 1 + [-0.3 0.3], '-', 'Color', orange, 'LineWidth', 1.6);
    end
    plot(ax, tt(ok), find(ok) - 1, '-', 'Color', orange, 'LineWidth', 1.0);
end
% T_pp arrow on the test-frequency trace
if isfinite(D.tPeakTx_ms(kT)) && isfinite(D.tPeakRx_ms(kT))
    ya = kT - 1 + amp + 0.13;
    plot(ax, [D.tPeakTx_ms(kT) D.tPeakRx_ms(kT)], [ya ya], 'k-', 'LineWidth', 0.9);
    plot(ax, D.tPeakTx_ms(kT), ya, 'k<', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
    plot(ax, D.tPeakRx_ms(kT), ya, 'k>', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
    text(ax, mean([D.tPeakTx_ms(kT) D.tPeakRx_ms(kT)]), ya + 0.08, 'T_{pp}', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
% near field marked on the lowest-frequency trace
x0 = D.tP_ms(1);  x1 = D.tS2S_ms(1);
if ~isfinite(x1) || x1 <= x0, x1 = D.tPeakRx_ms(1); end
if D.bump(1) > 0.02 && isfinite(x0) && isfinite(x1) && x1 > x0
    rectangle('Parent', ax, 'Position', [x0, -0.32, x1 - x0, 0.64], 'Curvature', [1 1], ...
        'LineStyle', ':', 'EdgeColor', magenta, 'LineWidth', 1.3);
    text(ax, x0, -0.53, 'Near-field effect', 'Color', magenta, 'FontSize', cfg.fontSize - 1, 'FontWeight', 'bold');
end
xlim(ax, [0 xmax]);  ylim(ax, [-0.6, max(n - 0.35, kT - 1 + amp + 0.35)]);   % room for the T_pp arrow
set(ax, 'YTick', [], 'TickDir', 'in', 'Box', 'on');
xlabel(ax, 'Time from transmitter start (ms)');
ylabel(ax, 'Transmitted (dashed) / received (solid), normalised');
title(ax, sprintf('%s %s (test at %g kHz)', letter, D.label, D.fTest / 1e3), ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.005 0]);
end

function hLeg = plotRelative(ax, sets, xKind, cfg)
% Vs relative to the test frequency against f (xKind 'f') or R_d ('Rd')
hold(ax, 'on');
xAll = [];
for s = 1:numel(sets)
    D = sets{s};
    if strcmp(xKind, 'f'), x = D.f / 1e3; else, x = D.Rd; end
    xAll = [xAll; x(isfinite(x))];                                                 %#ok<AGROW>
end
xl = [min(xAll) / 1.15, max(xAll) * 1.15];
bandColor = [0.91 0.91 0.91];                           % opaque: EPS cannot store transparency
if cfg.band > 0                                          % drawn first, so it lies under the data
    patch(ax, xl([1 2 2 1]), cfg.band * [-1 -1 1 1], bandColor, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
yline(ax, 0, '-', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.8, 'HandleVisibility', 'off');
hLeg.handles = gobjects(0);  hLeg.labels = {};
anyExcluded = false;
for s = 1:numel(sets)
    D = sets{s};
    if strcmp(xKind, 'f'), x = D.f / 1e3; xT = D.fTest / 1e3; else, x = D.Rd; xT = D.RdTest; end
    g = D.ok & isfinite(x) & isfinite(D.rel);
    h = plot(ax, x(g), D.rel(g), ['-' D.marker], 'Color', D.color, 'LineWidth', 1.2, ...
        'MarkerSize', 5, 'MarkerFaceColor', D.color, 'MarkerEdgeColor', 0.6 * D.color);
    hLeg.handles(end+1) = h;
    hLeg.labels{end+1} = sprintf('%s (test at %g kHz)', D.label, D.fTest / 1e3);
    bad = ~D.ok & isfinite(x) & isfinite(D.rel);
    if any(bad)
        plot(ax, x(bad), D.rel(bad), 'o', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5, 'LineWidth', 1.0, ...
            'HandleVisibility', 'off');
        anyExcluded = true;
    end
    if strcmp(xKind, 'f')
        xline(ax, xT, ':', 'Color', D.color, 'LineWidth', 1.3, 'HandleVisibility', 'off');
    else
        plot(ax, xT, 0, 'p', 'MarkerSize', 10, 'MarkerFaceColor', D.color, 'MarkerEdgeColor', 'k', ...
            'LineWidth', 0.8, 'HandleVisibility', 'off');
    end
end
if anyExcluded
    hLeg.handles(end+1) = plot(ax, NaN, NaN, 'o', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5, 'LineWidth', 1.0);
    hLeg.labels{end+1} = 'excluded (quality \neq ok)';
end
if cfg.band > 0
    hLeg.handles(end+1) = patch(ax, NaN, NaN, bandColor, 'EdgeColor', 'none');
    hLeg.labels{end+1} = sprintf('\\pm%g %% band', cfg.band);
end
set(ax, 'XScale', 'log', 'TickDir', 'in', 'Box', 'on', 'XMinorTick', 'on', 'YMinorTick', 'on');
xlim(ax, xl);
cand = [0.1 0.2 0.3 0.5 1 2 3 4 5 8 10 15 20 30 40 50 80 100 200];
ticks = cand(cand >= xl(1) & cand <= xl(2));
if numel(ticks) >= 2, set(ax, 'XTick', ticks); end
ylabel(ax, 'V_s relative to the test frequency (%)');
if strcmp(xKind, 'f')
    xlabel(ax, 'Excitation frequency, f (kHz)');
    title(ax, '(c) Frequency dependence of V_s', 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
        'Units', 'normalized', 'Position', [0 1.005 0]);
else
    if ~isempty(cfg.rdLine) && cfg.rdLine >= xl(1) && cfg.rdLine <= xl(2)
        xline(ax, cfg.rdLine, '--k', sprintf('R_d = %g', cfg.rdLine), 'LineWidth', 1.0, ...
            'LabelVerticalAlignment', 'bottom', 'LabelOrientation', 'horizontal', 'HandleVisibility', 'off');
    end
    xlabel(ax, 'Wavelengths between the tips, R_d = L_{tt} f / V_s');
    title(ax, '(d) Same data versus R_d (stars: test frequencies)', 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.005 0]);
end
grid(ax, 'off');
end

function s = provenance(sets)
% footnote: where the plotted numbers come from, as recorded in the workbooks
parts = cell(1, numel(sets));
for k = 1:numel(sets)
    D = sets{k};
    p = sprintf('%s: %s', D.label, D.name);
    if ~D.hasParameters
        p = [p ', Parameters sheet missing (data type not recorded)'];                  %#ok<AGROW>
    elseif isempty(D.dataType) || strcmpi(D.dataType, 'NaN')
        p = [p ', data type not recorded'];                                             %#ok<AGROW>
    else
        p = [p ', ' D.dataType];                                                        %#ok<AGROW>
    end
    if isfinite(D.nfScale), p = sprintf('%s, near-field scale %g', p, D.nfScale); end
    if isfinite(D.variation) && D.variation > 0, p = sprintf('%s, wave variation %g %%', p, 100 * D.variation); end
    nU = nnz(D.userSet);
    if nU > 0, p = sprintf('%s, T_pp entered by the user at %d of %d frequencies (*)', p, nU, numel(D.f)); end
    parts{k} = p;
end
s = ['Data: ' strjoin(parts, '   |   ')];
end

% =========================================================================
%                              REPORT AND CSV
% =========================================================================
function printComparison(sets, cfg, fid)
fprintf(fid, '\n=== Frequency sweeps compared (Vs from %s) ===\n', cfg.method);
for s = 1:numel(sets)
    D = sets{s};
    fprintf(fid, '%s  (%s)  test frequency %g kHz, Vs there %.2f m/s%s\n', D.label, D.name, ...
        D.fTest / 1e3, D.VsTest, ternaryText(D.testInSweep, '', ' (interpolated)'));
    fprintf(fid, '  %8s %10s %10s %10s %8s %8s %8s\n', 'f kHz', 'Ts us', 'Vs m/s', 'rel %', 'R_d', 'quality', 'entered');
    for k = 1:numel(D.f)
        fprintf(fid, '  %8.2f %10.2f %10.2f %10.2f %8.3f %8s %8s\n', D.f(k) / 1e3, 1e6 * D.Ts(k), D.Vs(k), ...
            D.rel(k), D.Rd(k), ternaryText(D.ok(k), 'ok', 'check'), ternaryText(D.userSet(k), 'yes', 'no'));
    end
end
fprintf(fid, '\n');
end

function writeComparisonCsv(sets, cfg, file)
fid = fopen(file, 'w');
if fid < 0, error('BEC:save', 'Cannot write %s (file open in another program?).', file); end
fprintf(fid, 'set,workbook,f_kHz,Ts_%s_us,Vs_m_s,Vs_rel_to_test_pct,R_d,quality,user_entered,test_f_kHz\n', cfg.method);
for s = 1:numel(sets)
    D = sets{s};
    for k = 1:numel(D.f)
        fprintf(fid, '"%s","%s",%.4f,%.4f,%.4f,%.4f,%.5f,%s,%d,%.4f\n', D.label, D.name, D.f(k) / 1e3, ...
            1e6 * D.Ts(k), D.Vs(k), D.rel(k), D.Rd(k), ternaryText(D.ok(k), 'ok', 'check'), D.userSet(k), D.fTest / 1e3);
    end
end
fclose(fid);
end

function out = ternaryText(c, a, b)
if c, out = a; else, out = b; end
end
