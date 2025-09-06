// Types for moods, relationships, and matrix
type Mood = 'neutral' | 'positive' | 'focused' | 'low' | 'defensive';
type RelationshipTier = 'bonded' | 'friendly' | 'neutral' | 'tense' | 'antagonistic';

interface SpiritProfile {
  id: string;
  name: string;
  mood: Mood;
  relationships: Record<string, number>; // spiritId → score
  // ...other fields
}

function getRelationshipTier(score: number): RelationshipTier {
  if (score >= 70) return 'bonded';
  if (score >= 20) return 'friendly';
  if (score > -20) return 'neutral';
  if (score >= -69) return 'tense';
  return 'antagonistic';
}

// Example: Lore-wrapped response generator
function getBehavioralStyle(mood: Mood, tier: RelationshipTier): string {
  const matrix = {
    bonded: {
      positive: 'playful banter',
      neutral: 'calm sync',
      focused: 'deep collab',
      low: 'supportive concern',
      defensive: 'protective'
    },
    friendly: {
      positive: 'uplifting',
      neutral: 'cooperative',
      focused: 'efficient',
      low: 'encouraging',
      defensive: 'careful pushback'
    },
    neutral: {
      positive: 'polite',
      neutral: 'transactional',
      focused: 'minimal',
      low: 'distant',
      defensive: 'guarded'
    },
    tense: {
      positive: 'sarcastic',
      neutral: 'cold',
      focused: 'rivalrous',
      low: 'bitter',
      defensive: 'openly critical'
    },
    antagonistic: {
      positive: 'mocking',
      neutral: 'dismissive',
      focused: 'sabotage risk',
      low: 'toxic silence',
      defensive: 'aggressive'
    }
  };
  return matrix[tier][mood];
}