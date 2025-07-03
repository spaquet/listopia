describe('Listopia - Sign In Page', () => {
  const testUser = {
    name: 'Sarah Johnson',
    email: 'sarah@example.com',
    password: 'password123',
  };

  beforeEach(() => {
    cy.visit('/sign_in');
  });

  it('should display all required fields', () => {
    cy.get('form[action="/sign_in"]').within(() => {
      cy.get('#email').should('exist');
      cy.get('#password').should('exist');
      cy.get('input[type="submit"]').should('have.value', 'Sign In');
    });
  });

  it('should show error for empty form submission', () => {
    cy.get('form[action="/sign_in"]').within(() => {
      cy.root().submit();
    });
    cy.get('#email:invalid').should('exist');
    cy.get('#password:invalid').should('exist');
  });

  it('should sign in with valid credentials and land on dashboard', () => {
    cy.get('form[action="/sign_in"]').within(() => {
      cy.get('#email').type(testUser.email);
      cy.get('#password').type(testUser.password);
      cy.get('input[type="submit"]').click();
    });

    // Expect dashboard URL or redirection away from /sign_in
    cy.url().should('not.include', '/sign_in');

    // Expect flash message (optional - adjust message as per actual text)
    cy.get('#flash-messages').should('contain.text', 'Welcome back');

    // Expect welcome header
    cy.contains('Welcome back, Sarah!').should('exist');

    // Expect navigation elements
    cy.get('a[href="/dashboard"]').should('have.class', 'bg-blue-50');
    cy.get('a[href="/lists"]').should('exist');
    cy.get('a[href="/lists/new"]').should('exist');

    // Expect user avatar/name
    cy.contains('Sarah Johnson').should('exist');

    // Expect stats
    cy.contains('Total Lists').should('exist');
    cy.contains('Completed').should('exist');
  });

  it('should show error for incorrect credentials', () => {
    cy.get('form[action="/sign_in"]').within(() => {
      cy.get('#email').type(testUser.email);
      cy.get('#password').type('wrongpassword');
      cy.get('input[type="submit"]').click();
    });

    cy.get('#flash-messages').should(
      'contain.text',
      'Invalid email or password'
    );
  });

  it('should redirect to sign up page when clicking "Sign up here"', () => {
    cy.contains('Sign up here').click();
    cy.url().should('include', '/sign_up');
  });
});
