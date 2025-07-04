describe('Listopia Landing Page', () => {
  beforeEach(() => {
    cy.visit('/');
  });

  it('should load the page with correct title', () => {
    cy.title().should('eq', 'Listopia');
  });

  it('should display the logo and brand name', () => {
    cy.get('a[href="/"]').within(() => {
      cy.get('span').contains('L');
      cy.get('span').contains('Listopia');
    });
  });

  it('should display navigation links', () => {
    cy.get('a[href="/sign_in"]').contains('Sign In');
    cy.get('a[href="/sign_up"]').contains('Sign Up');
  });

  it('should navigate to Sign In page when Sign In is clicked', () => {
    cy.get('nav a[href="/sign_in"]').click();
    cy.url().should('include', '/sign_in');
  });

  it('should navigate to Sign Up page when Sign Up is clicked', () => {
    cy.get('nav a[href="/sign_up"]').click();
    cy.url().should('include', '/sign_up');
  });

  it('should display hero heading and description', () => {
    cy.contains('Where Lists Come to');
    cy.contains('Create, share, and collaborate on lists');
  });

  it('should have "Get Started Free" and "Sign In" buttons in hero section', () => {
    cy.get('a[href="/sign_up"]').contains('Get Started Free');
    cy.get('a[href="/sign_in"]').contains('Sign In');
  });

  it('should navigate to Sign Up when "Get Started Free" is clicked', () => {
    cy.contains('Get Started Free').click();
    cy.url().should('include', '/sign_up');
  });

  it('should display all feature sections with correct content', () => {
    const features = [
      {
        title: 'Smart Lists',
        description:
          'Create dynamic lists with different item types, priorities, and due dates.',
      },
      {
        title: 'Real-time Collaboration',
        description:
          'Share lists and collaborate in real-time with your team or family.',
      },
      {
        title: 'Lightning Fast',
        description:
          'Built with Rails 8 and Hotwire for instant updates without page refreshes.',
      },
    ];

    features.forEach((feature) => {
      cy.contains(feature.title);
      cy.contains(feature.description);
    });
  });
});
