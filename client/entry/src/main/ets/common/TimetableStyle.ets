export interface TimetableTone {
  top: string;
  bottom: string;
  edge: string;
  ink: string;
}

/** Only occupied periods have surfaces. Shared geometry keeps labels and spanning cards aligned. */
export class TimetableStyle {
  static readonly SLOT_HEIGHT: number = 60;
  static readonly BAND_GAP: number = 14;
  static readonly CARD_GAP: number = 8;
  // Low-contrast separators keep the seven day columns legible without
  // reintroducing the white grid surfaces removed from the timetable.
  static readonly DAY_DIVIDER: string = '#24526D83';
  static readonly TONES: TimetableTone[] = [
    { top: '#DEEAFB', bottom: '#B6D3F0', edge: '#82A9CF', ink: '#234C76' },
    { top: '#E9E4F8', bottom: '#CDC3EA', edge: '#A397C5', ink: '#514174' },
    { top: '#DDEFE9', bottom: '#B4D8CC', edge: '#81B1A2', ink: '#285B51' },
    { top: '#F4EADB', bottom: '#E6CEAB', edge: '#BDA077', ink: '#705227' },
    { top: '#DCEBF0', bottom: '#B6D5DF', edge: '#83ACBC', ink: '#305A6B' }
  ];
  static readonly CONFLICT: TimetableTone = {
    top: '#F5E1E8', bottom: '#E6BFCB', edge: '#BD8A9B', ink: '#853B54'
  };

  static tone(courseId: number, conflict: boolean = false): TimetableTone {
    return conflict ? TimetableStyle.CONFLICT : TimetableStyle.TONES[Math.abs(courseId) % TimetableStyle.TONES.length];
  }

  static sectionTop(section: number): number {
    return (section - 1) * TimetableStyle.SLOT_HEIGHT + Math.floor((section - 1) / 4) * TimetableStyle.BAND_GAP;
  }

  static blockHeight(start: number, end: number): number {
    return TimetableStyle.sectionTop(end) + TimetableStyle.SLOT_HEIGHT - TimetableStyle.sectionTop(start) - TimetableStyle.CARD_GAP;
  }

  static totalHeight(): number { return TimetableStyle.sectionTop(12) + TimetableStyle.SLOT_HEIGHT; }
}
