module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation changes
        'style',    // Code style changes (formatting, etc.)
        'refactor', // Code refactoring
        'perf',     // Performance improvements
        'test',     // Adding or updating tests
        'chore',    // Maintenance tasks
        'ci',       // CI/CD changes
        'build',    // Build system changes
        'revert',   // Revert a previous commit
        'security'  // Security-related changes
      ]
    ],
    'subject-case': [0], // Allow any case for subject
    'body-max-line-length': [0], // No limit on body line length
    'footer-max-line-length': [0], // No limit on footer line length
  },
};
