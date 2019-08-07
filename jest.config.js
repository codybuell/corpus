module.exports = {
  roots: ['<rootDir>/src'],
  setupFilesAfterEnv: ['<rootDir>/src/jest/setup.ts'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest',
  },
};
