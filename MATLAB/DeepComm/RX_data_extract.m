clc;
clearvars;
close all;

% Parameters

% Parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
no_of_ofdm_symbols = 800;
size_of_FFT = 64;
cp_length = 16;
no_of_subcarriers = 48;
total_symbols = no_of_ofdm_symbols * no_of_subcarriers;
mod_order = 2;
bit_per_symbol = log2(mod_order);
total_no_bits = total_symbols * bit_per_symbol;
dec_type = 'MAP'; %'turbo'; %'MAP'
encoded_no_bits = 0.5 * total_no_bits; %(total_no_bits - 12) / 3;
blk_len = 10;
total_no_of_samples = no_of_ofdm_symbols * (size_of_FFT + cp_length);
no_of_pilot_carriers = 4;
subcarrier_locations = [7:32 34:59];
pilot_carriers = [12 26 40 54];
pilot_values = zeros(size_of_FFT, 1);
pilot_values(pilot_carriers, 1) = [1; 1; 1; -1];
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Extraction of the received data
stringTX = strcat("TX.bin");
stringRX = strcat("RX.bin");

TX = read_complex_binary(stringTX);
RX = read_complex_binary(stringRX);
% RX = [TX; TX; TX; TX; TX];

k = 1;
pow = zeros(length(RX), 1);
pkt_received = 0;

BER = [];

while length(RX) > total_symbols + 320 % 320 is the extra preamble

    % Power Trigger
    pow(k) = abs(RX(k) * conj(RX(k)));

    if k < 50000
        k = k + 1;
        continue;
    elseif pow(k) - pow(k - 1000) < 0.0012
        k = k + 1;
        continue;
    end

    % STS Packet Detection
    window_size = 16;
    count = 0;
    i = k;

    while count < 10
        corr = (sum(RX(i:i + window_size - 1) .* conj(RX(i + 16:i + 16 + window_size - 1))));
        corr = corr / (sum(RX(i:i + window_size - 1) .* conj(RX(i:i + window_size - 1))));

        if corr > 1.001
            count = count + 1;
        else
            count = 0;
        end

        i = i + 1;
    end

    st_id = i +16;

    % LTS Symbol Alignment
    L = zeros(200, 1);

    LTS = open('LTS.mat');
    LTS = LTS.LTS;
    lts = ifft(fftshift(LTS(1:size_of_FFT, 1)), size_of_FFT);

    for j = 1:200
        L(j) = sum(RX(st_id + j - 1:st_id + j - 1 +63) .* conj(lts));
    end

    [~, lt_id1] = max(L);
    L(lt_id1) = 0;
    [~, lt_id2] = max(L);
    lt_id = min(lt_id1, lt_id2);

    lt_id = st_id + lt_id - 1 - 16;

    sts_start_id = lt_id - 160;
    sts_end_id = lt_id - 1;

    lts1_start_id = lt_id;
    lts1_end_id = lt_id + 79;

    lts2_start_id = lt_id + 80;
    lts2_end_id = lt_id + 159;

    data_start_id = lt_id + 160;
    data_end_id = data_start_id + total_no_of_samples - 1;

    % Packet Extraction
    pkt_received = pkt_received + 1;
    sts = RX(sts_start_id:sts_end_id);
    lts1 = RX(lts1_start_id:lts1_end_id);
    lts2 = RX(lts2_start_id:lts2_end_id);
    y = RX(data_start_id:data_end_id);

    fprintf('Packet Receieved %d\n', pkt_received);

    % Coarse Frequency offset
    alpha = (1/16) * angle(sum(conj(sts(1:144)) .* sts(17:160)));

    lts1 = lts1 .* exp(-1j .* (0:79)' * alpha);
    lts2 = lts2 .* exp(-1j .* (80:159)' * alpha);
    y = y .* exp(-1j .* (160:159 + total_no_of_samples)' * alpha);

    fprintf('Frequency Corrected of Packet %d\n', pkt_received);

    % Data Arranged
    LTS1 = fftshift(fft(lts1(cp_length + 1:size_of_FFT + cp_length, 1)));
    LTS2 = fftshift(fft(lts2(cp_length + 1:size_of_FFT + cp_length, 1)));

    y = reshape(y, size_of_FFT + cp_length, no_of_ofdm_symbols);
    Y = zeros(size_of_FFT, no_of_ofdm_symbols);

    for i = 1:no_of_ofdm_symbols
        Y(:, i) = fftshift(fft(y(cp_length + 1:size_of_FFT + cp_length, i)));
    end

    % Channel Estimation
    H = zeros(size_of_FFT, 1);

    for j = subcarrier_locations
        H(j) = 0.5 * (LTS1(j) + LTS2(j)) * sign(LTS(j));
    end

    % Channel Equalization and Phase Offset Correction
    Pilots = open('Pilots.mat');
    Pilots = Pilots.Pilots;
    detected_symbols = zeros(total_symbols, 1);
    l = 1;

    for i = 1:no_of_ofdm_symbols
        theta = angle(sum(conj(Y(pilot_carriers, i)) .* Pilots(:, i) .* H(pilot_carriers, 1)));

        for j = subcarrier_locations

            if ~(any(pilot_carriers(:) == j))
                detected_symbols(l, 1) = (Y(j, i) / H(j)) * exp(1j * theta);
                l = l + 1;
            end

        end

    end



    %Constellation View

    % Symbols that were transmitted
    mod_symbols = open('mod_symbols.mat');
    mod_symbols = mod_symbols.mod_symbols;
    data_tx = qamdemod(mod_symbols, mod_order, 'UnitAveragePower', true);
    
    color_map = jet(mod_order);
    figure();
    hold on;
    grid on;
    for i = 1:mod_order
        scatter(real(detected_symbols(data_tx == i-1)), imag(detected_symbols(data_tx == i-1)),[],rand(1,3))

    end

    % Decoder
    demod_data = -qamdemod(detected_symbols, mod_order, 'OutputType', 'llr', 'UnitAveragePower', true);
    decoded_data = Decoder(demod_data, dec_type, encoded_no_bits, blk_len);
    data_to_encode = open('data_input.mat');
    data_to_encode = data_to_encode.data_input;
    fprintf("The decoded BER is : %1.4f\n", biterr(decoded_data, data_to_encode) / encoded_no_bits)

    RX(1:data_end_id) = [];

    break;
end

% %     mod_symbols = open('mod_symbols.mat');
% %     mod_symbols = mod_symbols.mod_symbols;
%         figure()
%         hold on;
%     % %
%         one_bit = detected_symbols(mod_symbols==1);
%         zero_bit = detected_symbols(mod_symbols==-1);
%         scatter(real(one_bit),imag(one_bit),'b')
%         scatter(real(zero_bit),imag(zero_bit),'r')

%         demod_data = qamdemod(mod_symbols, mod_order, 'UnitAveragePower', true);
%
%         figure;
%         scatter(real(detected_symbols(demod_data == 0)), imag(detected_symbols(demod_data == 0)),'r')
%         hold on;
% %         scatter(real(mod_symbols(demod_data == 0)), imag(mod_symbols(demod_data == 0)))
%
% %      figure;
%         scatter(real(detected_symbols(demod_data == 1)), imag(detected_symbols(demod_data == 1)),'b')
% %         hold on;
% %         scatter(real(mod_symbols(demod_data == 1)), imag(mod_symbols(demod_data == 1)))
%
% %          figure;
%         scatter(real(detected_symbols(demod_data == 2)), imag(detected_symbols(demod_data == 2)),'g')
%         hold on;
%         scatter(real(mod_symbols(demod_data == 2)), imag(mod_symbols(demod_data == 2)))

%          figure;
%         scatter(real(detected_symbols(demod_data == 3)), imag(detected_symbols(demod_data == 3)),'k')
%         hold on;
%         scatter(real(mod_symbols(demod_data == 3)), imag(mod_symbols(demod_data == 3)))

%     scatter(real(detected_symbols), imag(detected_symbols))

%
% %
% % % Plot the received data frequency response
% % figure();
% % plot(10*log10(abs(fftshift(pwelch(resample(RX(1:1e6),1,1),64)))))
% % xlabel('Samples')
% % ylabel('Mag Response');
% % title('Received Signal Frequency Response')
% % grid on;
%
%
% % Correlate and extract samples
% x = TX;
% y = acorr(TX,RX);
%
% % %Frequency Offset Correction
% % S = 0;
% % for i = 1:144
% %     S = S + y(i,1)'*y(i+16);
% % end
% % angleS = angle(S);
% % alpha = angleS/16;
% %
% % for i = 161:length(x)
% %     y(1) = y(161,1)*exp(-1j*(i - 160-1)*alpha);
% % end
% x = x(161:end);
% % y = y(1:length(x));
% y = y(161:end);gm
%
% % Channel Estimation
% h = Equalization_NLMS(x,y);
% H = fftshift(fft(h));
%
% % % Plot the time domain channel response
% % figure()
% % plot(abs(h))
% % xlabel('Samples')
% % ylabel('Mag Response');
% % title('Channel Impulse Response')
% % grid on;
% %
% %
% % % Plot the frequency domain channel response
% % figure()
% % plot(abs(H))
% % xlabel('Samples')
% % ylabel('Mag Response');
% % title('Channel Frequency Response')
% % grid on;
% %
%
%
%
% % Remove CP from the received samples
% y = reshape(y, size_of_FFT+cp_length, no_of_ofdm_symbols);
%
% % Take the FFT of the reveived time samples
% Y = zeros(size_of_FFT, no_of_ofdm_symbols);
% for i = 1:no_of_ofdm_symbols
%     Y(:,i) = fftshift(fft(y(cp_length+1:size_of_FFT+cp_length,i)));
% end
%
% % Extract from the subcarriers
% detected_symbols = zeros(total_symbols,1);
% k = 1;
% for i = 1:no_of_ofdm_symbols
%     for j = [7:32 34:58]
%         detected_symbols(k,1) = Y(j,i)/H(j,1);
%         k = k+1;
%     end
% end
%
% % TX Data
% mod_symbols = open('mod_symbols.mat');
% mod_symbols = mod_symbols.mod_symbols;
% %
% % figure()
% % subplot(1,2,1)
% % scatter(real(mod_symbols), imag(mod_symbols));
% % xlabel('Real')
% % ylabel('Imaginary')
% % title('TX Data')
% %
% % subplot(1,2,2)
% % scatter(real(detected_symbols), imag(detected_symbols));
% % xlabel('Real')
% % ylabel('Imaginary')
% % title('RX Data')
% %
% % sgtitle('Constellation')
%
%
% figure()
% hold on;
% % for i = 1: 10000
% %     if mod_symbols(i) == 1
% %         scatter(real(detected_symbols(i)), imag(detected_symbols(i)),'b');
% %     else
% %         scatter(real(detected_symbols(i)), imag(detected_symbols(i)),'r');
% %     end
% % end
%
% one_bit = detected_symbols(mod_symbols==1);
% zero_bit = detected_symbols(mod_symbols==-1);
% scatter(real(one_bit),imag(one_bit),'b')
% scatter(real(zero_bit),imag(zero_bit),'r')
% xlabel('Real')
% ylabel('Imaginary')
% title('RX Data')
% grid on;
% sgtitle('Constellation')
