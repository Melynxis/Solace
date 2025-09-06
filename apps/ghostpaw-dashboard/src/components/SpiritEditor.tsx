import React, { useState } from 'react';

type Spirit = {
  id: number;
  name: string;
  role: string;
  state: string;
  meta: any;
};

type Props = {
  spirit: Spirit;
  userRole: 'admin' | 'sub-admin' | 'user' | 'guest';
  onUpdate: (update: Partial<Spirit>) => void;
  onDelete: (id: number) => void;
};

export const SpiritEditor: React.FC<Props> = ({ spirit, userRole, onUpdate, onDelete }) => {
  const [editing, setEditing] = useState(false);
  const [meta, setMeta] = useState(spirit.meta);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const handleSave = () => {
    onUpdate({ id: spirit.id, meta });
    setEditing(false);
  };

  const handleDelete = () => {
    if (!confirmDelete) {
      setConfirmDelete(true);
      setTimeout(() => setConfirmDelete(false), 3000); // Reset after 3s
      return;
    }
    onDelete(spirit.id);
  };

  if (userRole !== 'admin' && userRole !== 'sub-admin') {
    return <div>You do not have permission to edit this spirit.</div>;
  }

  return (
    <div className="spirit-editor-panel">
      <h2>Edit Spirit: {spirit.name}</h2>
      <label>
        Traits:
        <input
          type="text"
          value={meta.personality?.traits?.join(', ') || ''}
          onChange={e => setMeta({
            ...meta,
            personality: {
              ...meta.personality,
              traits: e.target.value.split(',').map(s => s.trim())
            }
          })}
        />
      </label>
      <label>
        Tone:
        <input
          type="text"
          value={meta.personality?.tone || ''}
          onChange={e => setMeta({
            ...meta,
            personality: { ...meta.personality, tone: e.target.value }
          })}
        />
      </label>
      <label>
        Relationships:
        <input
          type="text"
          value={meta.relationships?.join(', ') || ''}
          onChange={e => setMeta({ ...meta, relationships: e.target.value.split(',').map(s => s.trim()) })}
        />
      </label>
      {/* Add more fields as needed */}
      <div style={{ marginTop: '1em' }}>
        <button onClick={handleSave}>Save Changes</button>
        <button
          style={{ marginLeft: '1em', color: confirmDelete ? 'red' : undefined }}
          onClick={handleDelete}
        >
          {confirmDelete ? 'Click again to confirm DELETE' : 'Delete Spirit'}
        </button>
      </div>
    </div>
  );
};
