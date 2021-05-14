function [f_window_bsb, f_window_pass,f_idx_bsb,f_idx_pass] = cal_f_index(f_start,f_stop,delta_f,NFFT)

idx = [];
for idx_band = 1:length(f_start)
  idx      = [idx floor(f_start(idx_band)/delta_f):floor(f_stop(idx_band)/delta_f)];
end


f_window = zeros(1,NFFT);
f_window(idx) = ones(1,length(idx));
f_window_mirror = fliplr(f_window(2:end));
f_window_bsb  = [f_window 0 f_window_mirror];
% symmetry as in 0, 1 2 3, 4 ,-3 -2 -1

scale = NFFT/sum(f_window_bsb);
%scale = 1;
f_window_bsb = f_window_bsb*scale; % make sure the total power is still the same 

f_window_pass = fftshift(f_window);


f_idx_bsb = find(f_window_bsb~=0);
f_idx_pass = find(f_window_pass~=0);

