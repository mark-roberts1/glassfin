/**
 * The badges Infuse puts under a title: what you are about to play, in the
 * terms that decide whether it will play well — resolution, dynamic range,
 * codec, and how many channels of audio.
 *
 * On the BC-250 this is not trivia. HEVC and 4K are exactly the combination
 * that has to be decoded on six CPU cores, so seeing it before pressing play
 * is genuinely useful.
 */

import type { Item, MediaStream } from './jellyfin';

function resolutionLabel(video: MediaStream): string | null {
  const height = video.Height ?? 0;
  if (height >= 2000) return '4K';
  if (height >= 1400) return '1440p';
  if (height >= 1000) return '1080p';
  if (height >= 700) return '720p';
  return height > 0 ? 'SD' : null;
}

function rangeLabel(video: MediaStream): string | null {
  switch (video.VideoRangeType) {
    case 'DOVI':
    case 'DOVIWithHDR10':
      return 'Dolby Vision';
    case 'HDR10':
      return 'HDR10';
    case 'HDR10Plus':
      return 'HDR10+';
    case 'HLG':
      return 'HLG';
    default:
      return null;
  }
}

function codecLabel(codec: string | undefined): string | null {
  if (!codec) return null;
  const known: Record<string, string> = {
    h264: 'H.264',
    hevc: 'HEVC',
    h265: 'HEVC',
    av1: 'AV1',
    vp9: 'VP9',
    mpeg2video: 'MPEG-2',
    eac3: 'E-AC-3',
    ac3: 'AC-3',
    truehd: 'TrueHD',
    dts: 'DTS',
    dtshd: 'DTS-HD',
    aac: 'AAC',
    flac: 'FLAC',
    opus: 'Opus',
    mp3: 'MP3'
  };
  return known[codec.toLowerCase()] ?? codec.toUpperCase();
}

function channelLabel(audio: MediaStream): string | null {
  if (audio.ChannelLayout) return audio.ChannelLayout.toUpperCase();
  switch (audio.Channels) {
    case 1:
      return 'Mono';
    case 2:
      return 'Stereo';
    case 6:
      return '5.1';
    case 8:
      return '7.1';
    default:
      return audio.Channels ? `${audio.Channels}ch` : null;
  }
}

export interface MediaBadges {
  video: string[];
  audio: string[];
  subtitleLanguages: string[];
}

export function mediaBadges(item: Item): MediaBadges {
  const streams = item.MediaSources?.[0]?.MediaStreams ?? [];
  const video = streams.find((stream) => stream.Type === 'Video');
  const audio = streams.find((stream) => stream.Type === 'Audio' && stream.IsDefault) ??
    streams.find((stream) => stream.Type === 'Audio');

  const subtitleLanguages = [
    ...new Set(
      streams
        .filter((stream) => stream.Type === 'Subtitle' && stream.Language)
        .map((stream) => stream.Language as string)
    )
  ];

  return {
    video: video ? [resolutionLabel(video), rangeLabel(video), codecLabel(video.Codec)].filter((v): v is string => !!v) : [],
    audio: audio ? [codecLabel(audio.Codec), channelLabel(audio)].filter((v): v is string => !!v) : [],
    subtitleLanguages
  };
}
