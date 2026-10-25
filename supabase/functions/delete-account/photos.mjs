// All paths are derived from the verified owner, never from the request body.
export function accountPhotos(admin) {
  return {
    async prepare(userId) {
      const { data, error } = await admin.rpc('begin_account_deletion', { p_user: userId });
      if (error || !data) throw new Error(error?.message === 'DELETE_IN_PROGRESS' ? 'DELETE_IN_PROGRESS' : 'ACCOUNT_LOCK_FAILED');
      return data;
    },
    async cleanup(userId) {
      const bucket = admin.storage.from('profile-photos');
      const { data, error } = await bucket.list(userId, { limit: 100 });
      if (error || !Array.isArray(data) || data.length >= 100) throw new Error('PHOTO_CLEANUP_FAILED');
      const paths = data.map(file => {
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$/.test(file.name)) throw new Error('PHOTO_CLEANUP_FAILED');
        return `${userId}/${file.name}`;
      });
      if (paths.length) {
        const removed = await bucket.remove(paths);
        if (removed.error) throw new Error('PHOTO_CLEANUP_FAILED');
      }
    },
    async restore(userId, token) {
      const { error } = await admin.rpc('abort_account_deletion', { p_user: userId, p_token: token });
      if (error) throw new Error('ACCOUNT_UNLOCK_FAILED');
    },
  };
}
